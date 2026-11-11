import AVFoundation
import AppKit
import CueCore
import QuartzCore

// What the status line says about a clip; the system's own message goes to the log only.
enum LoadFailure: Equatable {
    case cannotLoad
    case playbackFailed
    // Warning only: the clip still plays.
    case pictureUnconfirmed
}

// What a logo number shows on the output.
enum LogoPicture {
    case image(CGImage)
    case loop(URL)

    var loop: URL? {
        if case .loop(let url) = self { url } else { nil }
    }
}

@MainActor
final class PlaybackEngine: Player {
    static let displayReadyTimeout: TimeInterval = 3
    static let parkSeekTimeout: TimeInterval = 1.5
    static let maxBreakMinutes: Double = 600

    var onEvent: (Command) -> Void = { _ in }
    var onLoadError: (Slot, URL, LoadFailure) -> Void = { _, _, _ in }
    var onLoopFailed: (URL) -> Void = { _ in }
    let window: OutputWindow
    // Read at GO, so a language switch never changes the projector until the next break.
    var defaultBreakTitle: String
    private(set) var breakTitle = ""

    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    private var logoFiles: [LogoFile?] = []
    // The image logos that decoded.
    private(set) var images: [URL: CGImage] = [:]
    private var loops: [URL: LoopLogo] = [:]
    // What the base logo layer shows, so LIVE matches the projector after an edit or Open.
    private(set) var basePicture: LogoPicture?
    // The loops the output shows as base and as cover; a cover fading out no longer counts.
    private var baseLoop: URL?
    private var coverLoop: URL?
    private var base: Base = .black
    // What the cover layers show, a logo that cannot load being black.
    private(set) var shownCover: Cover?
    // What the cover logo layer is painted with, kept while it fades out, so LIVE matches the projector.
    private(set) var coverPicture: LogoPicture?
    // The last cover change's fade in seconds; 0 is a cut.
    private(set) var coverFade: TimeInterval = 0
    // True while a GO's effects run, so its cover change cuts in the same transaction as the new base.
    private var applyingGo = false
    private var breakTimer: Timer?
    private var jobs: [Slot: LoadJob] = [:]
    // Bumped by every load and seek, so a superseded seek never reports the armed clip ready.
    private var seeks: [Slot: Int] = [:]
    // The seek generation each slot last reported ready for, so a late landing never reports twice.
    private var parked: [Slot: Int] = [:]
    private var observers: [NSObjectProtocol] = []

    init(defaultBreakTitle: String) {
        self.defaultBreakTitle = defaultBreakTitle
        for player in [playerA, playerB] {
            player.automaticallyWaitsToMinimizeStalling = false
            player.actionAtItemEnd = .pause
            player.isMuted = true
        }
        window = OutputWindow(playerA: playerA, playerB: playerB)
        let center = NotificationCenter.default
        observers.append(
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: nil, queue: .main) {
                [weak self] note in
                let item = note.object as? AVPlayerItem
                MainActor.assumeIsolated { self?.itemEnded(item) }
            })
        observers.append(
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: nil, queue: .main) {
                [weak self] note in
                let item = note.object as? AVPlayerItem
                let error = note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                let message = error?.localizedDescription ?? "unknown error"
                MainActor.assumeIsolated { self?.itemFailed(item, message: message) }
            })
    }

    func player(for slot: Slot) -> AVPlayer {
        slot == .a ? playerA : playerB
    }

    func url(_ slot: Slot) -> URL? {
        jobs[slot]?.url
    }

    func time(_ slot: Slot) -> (position: Double, duration: Double)? {
        let player = player(for: slot)
        guard let duration = player.currentItem?.duration.seconds, duration.isFinite else { return nil }
        let position = player.currentTime().seconds
        return (position.isFinite ? min(max(position, 0), duration) : 0, duration)
    }

    // Layers already showing a logo keep it; the new ones apply from the next cover or GO. One player per loop file.
    func setLogos(_ files: [LogoFile?]) {
        logoFiles = files
        // Decoded images stay; only a file new to the list is decoded.
        let wanted = Set(files.compactMap { file -> URL? in if case .image(let url)? = file { url } else { nil } })
        images = images.filter { wanted.contains($0.key) }
        for (index, file) in files.enumerated() {
            switch file {
            case .image(let url)? where images[url] == nil:
                images[url] = PreflightRunner.logoImage(at: url)
                if images[url] == nil { Log.info("picture \(index + 1) cannot be loaded: \(url.path)") }
            case .loop(let url)? where loops[url] == nil:
                addLoop(url)
                Log.info("picture \(index + 1) loops \(url.path)")
            default:
                break
            }
        }
        scheduleDrop()
    }

    func logo(_ number: Int) -> LogoPicture? {
        guard logoFiles.indices.contains(number - 1), let file = logoFiles[number - 1] else { return nil }
        switch file {
        case .image(let url): return images[url].map(LogoPicture.image)
        case .loop(let url): return .loop(url)
        }
    }

    // What a logo cue shows: Logo 1 or 2 only, so a slot never becomes the live item.
    func liveLogo(_ number: Int) -> LogoPicture? {
        (1...logoCount).contains(number) ? logo(number) : nil
    }

    func loopPlayer(_ url: URL) -> AVPlayer? {
        loops[url]?.player
    }

    // Loops whose player could not play their file; a cover press on them is refused.
    var failedLoops: Set<URL> {
        Set(loops.filter { $0.value.failed }.keys)
    }

    // A player built while its file was missing never recovers, so it is built again once off the output.
    func rebuildFailedLoops() {
        for (url, loop) in loops where loop.failed && !loop.running {
            loop.stop()
            window.removeLoop(url)
            addLoop(url)
            Log.info("logo loop \(url.lastPathComponent) built again")
        }
    }

    private func addLoop(_ url: URL) {
        let loop = LoopLogo(url: url)
        loop.onFailed = { [weak self] in self?.onLoopFailed(url) }
        loops[url] = loop
        window.addLoop(url, player: loop.player)
    }

    // Loads run after the commit, so the old live player never swaps items before its layer hides; returns switch ms.
    @discardableResult
    func apply(_ effects: [Effect], for label: String, receivedAt start: TimeInterval) -> Double? {
        let loads = effects.filter(\.isLoad)
        applyingGo = effects.contains(where: \.isShow)
        withoutAnimation { perform(effects.filter { !$0.isLoad }) }
        applyingGo = false
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        if !loads.isEmpty {
            CATransaction.flush()
            perform(loads)
        }
        let switches = effects.filter(\.isSwitch)
        guard !switches.isEmpty else { return nil }
        Log.deferred(String(format: "switch %@ -> %@ in %.1f ms", label, "\(switches)", ms))
        return ms
    }

    func load(_ slot: Slot, url: URL, at time: Double) {
        let player = player(for: slot)
        let job = LoadJob(url: url, time: time, item: AVPlayerItem(asset: AVURLAsset(url: url)))
        jobs[slot] = job
        seeks[slot, default: 0] += 1
        player.pause()
        player.replaceCurrentItem(with: job.item)
        Log.info("load \(slot) \(url.lastPathComponent) at \(time)")
        // Stays on for the item's lifetime so a failure during playback still reaches the control screen.
        job.statusObservation = job.item.observe(\.status, options: [.initial, .new]) { [weak self, weak job] _, _ in
            Self.onMain {
                guard let job else { return }
                self?.statusChanged(slot, job)
            }
        }
    }

    // A park seek on the hidden armed clip reports ready again once it lands, so GO shows the parked frame.
    func seek(_ slot: Slot, to time: Double) {
        seeks[slot, default: 0] += 1
        guard let job = jobs[slot], job.isReady, base != .clip(slot), let generation = seeks[slot] else {
            player(for: slot).seek(to: Self.cmTime(time), toleranceBefore: .zero, toleranceAfter: .zero)
            return
        }
        park(slot, job, at: time, generation: generation, retry: true)
    }

    // A seek that never lands would block GO for good: retry once, then report ready with an amber warning.
    private func park(_ slot: Slot, _ job: LoadJob, at time: Double, generation: Int, retry: Bool) {
        player(for: slot).seek(to: Self.cmTime(time), toleranceBefore: .zero, toleranceAfter: .zero) {
            [weak self] finished in
            Self.onMain {
                guard finished, let self, self.isPending(slot, job, generation) else { return }
                Log.info("parked \(slot) \(job.url.lastPathComponent) at \(time)")
                self.parkLanded(slot, job, generation)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.parkSeekTimeout) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isPending(slot, job, generation) else { return }
                let name = job.url.lastPathComponent
                if retry {
                    Log.info("park \(slot) \(name) at \(time) not done after \(Self.parkSeekTimeout) s, seeking again")
                    self.park(slot, job, at: time, generation: generation, retry: false)
                } else {
                    Log.info("park \(slot) \(name) at \(time) still not done, ready with the picture unconfirmed")
                    self.parkLanded(slot, job, generation)
                    self.report(slot, job.url, .pictureUnconfirmed, "park seek to \(time) not confirmed")
                }
            }
        }
    }

    private func isPending(_ slot: Slot, _ job: LoadJob, _ generation: Int) -> Bool {
        seeks[slot] == generation && parked[slot] != generation && jobs[slot] === job && base != .clip(slot)
    }

    private func parkLanded(_ slot: Slot, _ job: LoadJob, _ generation: Int) {
        parked[slot] = generation
        onEvent(.armedReady(slot, job.url, duration: Self.duration(of: job)))
    }

    func seek(_ slot: Slot, by delta: Double) {
        seeks[slot, default: 0] += 1
        let player = player(for: slot)
        guard let item = player.currentItem else { return }
        var target = max(0, player.currentTime().seconds + delta)
        if item.duration.seconds.isFinite { target = min(target, item.duration.seconds) }
        player.seek(to: Self.cmTime(target))
    }

    func play(_ slot: Slot) {
        player(for: slot).play()
    }

    func pause(_ slot: Slot) {
        player(for: slot).pause()
    }

    func show(_ base: Base) {
        self.base = base
        breakTimer?.invalidate()
        breakTimer = nil
        basePicture = nil
        switch base {
        case .black:
            window.showBase(clip: nil, logo: nil, breakScreen: false)
        case .logo(let number):
            basePicture = liveLogo(number)
            window.showBase(clip: nil, logo: basePicture, breakScreen: false)
        case .clip(let slot):
            window.showBase(clip: slot, logo: nil, breakScreen: false)
        case .breakScreen(let item, _):
            breakTitle = item.text ?? defaultBreakTitle
            updateBreak()
            window.showBase(clip: nil, logo: nil, breakScreen: true)
            if item.countdown { startBreakTimer() }
        }
        baseLoop = basePicture?.loop
        // A new base also cuts a cover fade, so nothing is left fading out.
        if shownCover == nil { coverPicture = nil }
        syncLoops(fadeOut: 0)
    }

    func setCover(_ cover: Cover?) {
        let picture: LogoPicture? = if case .logo(let number) = cover { logo(number) } else { nil }
        let shown: Cover? = cover != nil && picture == nil ? .black : cover
        let fade = ShowState.fadesCover(from: shownCover, to: shown, withGo: applyingGo)
        coverFade = fade ? ShowState.logoFade : 0
        window.showCover(logo: picture, black: shown == .black, fade: coverFade)
        shownCover = shown
        coverPicture = picture ?? (fade ? coverPicture : nil)
        coverLoop = picture?.loop
        syncLoops(fadeOut: fade && picture == nil ? ShowState.logoFade : 0)
    }

    // Restart-on-show: a loop runs only while the output shows it and rewinds to its first frame once hidden.
    private func syncLoops(fadeOut: TimeInterval) {
        for (url, loop) in loops {
            guard url == baseLoop || url == coverLoop else {
                loop.hide(after: fadeOut)
                continue
            }
            if !loop.running, !window.loopReady(url, cover: url != baseLoop) {
                Log.deferred("logo loop \(url.lastPathComponent) shown with its layer NOT ready for display")
            }
            loop.show()
        }
        scheduleDrop()
    }

    // After the switch commits, so tearing a loop down never runs inside a GO or cover transaction.
    private func scheduleDrop() {
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.dropUnusedLoops() } }
    }

    // A loop the logo list no longer names goes once it has stopped, never while the output still shows it.
    private func dropUnusedLoops() {
        let used = Set(logoFiles.compactMap { file -> URL? in if case .loop(let url)? = file { url } else { nil } })
        for (url, loop) in loops where !loop.running && !used.contains(url) {
            loop.stop()
            loops[url] = nil
            window.removeLoop(url)
        }
    }

    func setMuted(_ muted: Bool) {
        playerA.isMuted = muted
        playerB.isMuted = muted
    }

    private func isLoading(_ slot: Slot, _ job: LoadJob) -> Bool {
        jobs[slot] === job && !job.isReady && !job.failed
    }

    private func statusChanged(_ slot: Slot, _ job: LoadJob) {
        guard jobs[slot] === job, !job.failed else { return }
        switch job.item.status {
        case .readyToPlay:
            // Queued KVO blocks read the live status, so two of them can both see ready.
            guard !job.seeking else { return }
            job.seeking = true
            player(for: slot).seek(to: Self.cmTime(job.time), toleranceBefore: .zero, toleranceAfter: .zero) {
                [weak self] _ in
                Self.onMain { self?.preroll(slot, job) }
            }
        case .failed:
            job.failed = true
            job.displayObservation = nil
            report(slot, job.url, .cannotLoad, job.item.error?.localizedDescription ?? "unknown error")
        default:
            break
        }
    }

    private func preroll(_ slot: Slot, _ job: LoadJob) {
        guard isLoading(slot, job) else { return }
        let player = player(for: slot)
        // preroll raises unless the player itself is ready and paused.
        guard player.status == .readyToPlay, player.rate == 0 else {
            awaitDisplay(slot, job)
            return
        }
        player.preroll(atRate: 1) { [weak self] _ in
            Self.onMain { self?.awaitDisplay(slot, job) }
        }
    }

    private func awaitDisplay(_ slot: Slot, _ job: LoadJob) {
        guard isLoading(slot, job) else { return }
        job.displayObservation = window.playerLayer(slot).observe(\.isReadyForDisplay, options: [.initial, .new]) {
            [weak self, weak job] layer, _ in
            Self.onMain {
                guard let job, layer.isReadyForDisplay else { return }
                self?.ready(slot, job, pictureConfirmed: true)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displayReadyTimeout) { [weak self, weak job] in
            MainActor.assumeIsolated {
                guard let self, let job, self.isLoading(slot, job) else { return }
                self.ready(slot, job, pictureConfirmed: false)
                // Never block GO forever, but warn when a projector is attached and the frame is unconfirmed.
                if self.window.isVisible { self.report(slot, job.url, .pictureUnconfirmed, "picture not confirmed") }
            }
        }
    }

    private func ready(_ slot: Slot, _ job: LoadJob, pictureConfirmed: Bool) {
        guard isLoading(slot, job) else { return }
        job.isReady = true
        job.displayObservation = nil
        let duration = Self.duration(of: job)
        let picture =
            pictureConfirmed
            ? "hidden layer ready for display"
            : "hidden layer NOT ready for display after \(Self.displayReadyTimeout) s (output visible: \(window.isVisible))"
        Log.info("ready \(slot) \(job.url.lastPathComponent) duration \(duration), \(picture)")
        onEvent(.armedReady(slot, job.url, duration: duration))
    }

    private func report(_ slot: Slot, _ url: URL, _ failure: LoadFailure, _ message: String) {
        Log.info("error \(slot) \(url.lastPathComponent): \(message)")
        onLoadError(slot, url, failure)
    }

    private static func duration(of job: LoadJob) -> Double {
        let seconds = job.item.duration.seconds
        return seconds.isFinite ? seconds : .infinity
    }

    private func slot(of item: AVPlayerItem?) -> Slot? {
        guard let item else { return nil }
        return [Slot.a, .b].first { jobs[$0]?.item === item }
    }

    private func itemEnded(_ item: AVPlayerItem?) {
        guard let slot = slot(of: item) else { return }
        Log.info("ended \(slot)")
        onEvent(.liveEnded(slot))
    }

    private func itemFailed(_ item: AVPlayerItem?, message: String) {
        guard let slot = slot(of: item), let job = jobs[slot] else { return }
        report(slot, job.url, .playbackFailed, "playback failed: \(message)")
    }

    private func startBreakTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateBreak() }
        }
        RunLoop.main.add(timer, forMode: .common)
        breakTimer = timer
    }

    private func updateBreak() {
        guard case .breakScreen(let item, let startedAt) = base else { return }
        let countdown = Self.breakCountdown(item, startedAt: startedAt, now: Date())
        window.setBreak(title: breakTitle, countdown: countdown)
        if countdown == nil {
            breakTimer?.invalidate()
            breakTimer = nil
        }
    }

    static func breakCountdown(_ item: BreakItem, startedAt: Date, now: Date) -> String? {
        guard item.countdown else { return nil }
        let minutes = item.minutes.isFinite ? min(max(item.minutes, 0), maxBreakMinutes) : 0
        let left = startedAt.addingTimeInterval(minutes * 60).timeIntervalSince(now).rounded(.up)
        // Clamped before Int() so an odd clock or file can never trap.
        let seconds = left.isFinite ? Int(min(max(left, 0), maxBreakMinutes * 60)) : 0
        return seconds > 0 ? String(format: "%02ld:%02ld", seconds / 60, seconds % 60) : nil
    }

    private static func cmTime(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600)
    }

    private nonisolated static func onMain(_ body: @escaping @MainActor () -> Void) {
        DispatchQueue.main.async { MainActor.assumeIsolated(body) }
    }
}

// One muted, seamless loop per logo file; AVPlayerLooper keeps a fixed set of items, so memory stays flat.
@MainActor
private final class LoopLogo {
    let player = AVQueuePlayer()
    private let name: String
    private let looper: AVPlayerLooper
    private var observations: [NSKeyValueObservation] = []
    // Bumped by every show and hide, so a superseded rewind never runs.
    private var generation = 0
    private var rewinds = 0
    // The rewind seek still in flight; a show waits for it.
    private var pendingRewind: Int?
    private var prerolled = false
    // Playing, or still visible while a fade-out ends.
    private(set) var running = false
    var onFailed: () -> Void = {}

    init(url: URL) {
        name = url.lastPathComponent
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = false
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(asset: AVURLAsset(url: url)))
        observations.append(
            player.observe(\.currentItem?.status, options: [.initial, .new]) { [weak self] _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.preroll() } }
            })
        observations.append(
            looper.observe(\.status, options: [.new]) { [weak self, name] looper, _ in
                guard looper.status == .failed else { return }
                Log.info("logo loop \(name) cannot play: \(looper.error?.localizedDescription ?? "unknown error")")
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.onFailed() } }
            })
    }

    // A missing or unplayable file fails the looper; a ready one with no item has lost its items.
    var failed: Bool {
        looper.status == .failed || (looper.status == .ready && player.currentItem == nil)
    }

    func show() {
        generation += 1
        guard !running else { return }
        running = true
        // A show right after a hide plays once the rewind lands, never from a mid-loop frame that then jumps.
        if pendingRewind == nil { player.play() }
    }

    // After any fade-out, so a visible loop never jumps back to its first frame.
    func hide(after delay: TimeInterval) {
        guard running else { return }
        generation += 1
        let current = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.rewind(current) }
        }
    }

    func stop() {
        observations = []
        looper.disableLooping()
        player.pause()
        player.removeAllItems()
    }

    private func rewind(_ current: Int) {
        guard generation == current, running else { return }
        running = false
        prerolled = false
        player.pause()
        // A loop that never loaded has nothing to rewind, and its seek might never report back.
        guard player.currentItem != nil else { return }
        rewinds += 1
        let id = rewinds
        pendingRewind = id
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.rewound(id, finished: finished) } }
        }
    }

    // Only the latest seek counts: a newer one cancels the older, which then reports unfinished.
    private func rewound(_ id: Int, finished: Bool) {
        guard pendingRewind == id else { return }
        pendingRewind = nil
        if running {
            player.play()
        } else if finished {
            preroll()
        }
    }

    // Decoded ahead, so the next show starts on the first frame at once; preroll raises unless ready and paused.
    private func preroll() {
        guard !prerolled, !running, pendingRewind == nil, player.currentItem?.status == .readyToPlay,
            player.status == .readyToPlay, player.rate == 0
        else { return }
        prerolled = true
        player.preroll(atRate: 1) { [name] finished in
            Log.deferred("logo loop \(name) \(finished ? "prerolled" : "preroll interrupted")")
        }
    }
}

@MainActor
private final class LoadJob {
    let url: URL
    let time: Double
    let item: AVPlayerItem
    var statusObservation: NSKeyValueObservation?
    var displayObservation: NSKeyValueObservation?
    var seeking = false
    var isReady = false
    var failed = false

    init(url: URL, time: Double, item: AVPlayerItem) {
        self.url = url
        self.time = time
        self.item = item
    }
}

extension Effect {
    fileprivate var isLoad: Bool {
        if case .load = self { true } else { false }
    }

    fileprivate var isShow: Bool {
        if case .show = self { true } else { false }
    }

    fileprivate var isSwitch: Bool {
        switch self {
        case .show, .setCover: true
        default: false
        }
    }
}
