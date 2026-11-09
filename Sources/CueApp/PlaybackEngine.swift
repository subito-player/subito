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

@MainActor
final class PlaybackEngine: Player {
    static let displayReadyTimeout: TimeInterval = 3
    static let parkSeekTimeout: TimeInterval = 1.5
    static let maxBreakMinutes: Double = 600

    var onEvent: (Command) -> Void = { _ in }
    var onLoadError: (Slot, URL, LoadFailure) -> Void = { _, _, _ in }
    let window: OutputWindow
    // Read at GO, so a language switch never changes the projector until the next break.
    var defaultBreakTitle: String
    private(set) var breakTitle = ""

    private let playerA = AVPlayer()
    private let playerB = AVPlayer()
    private var logos: [CGImage?] = []
    private var base: Base = .black
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

    // Layers already showing a logo keep their image; the new ones apply from the next cover or GO.
    func setLogos(_ urls: [URL]) {
        logos = urls.enumerated().map { index, url in
            let image = PreflightRunner.logoImage(at: url)
            if image == nil { Log.info("logo \(index + 1) cannot be loaded: \(url.path)") }
            return image
        }
    }

    func logo(_ number: Int) -> CGImage? {
        logos.indices.contains(number - 1) ? logos[number - 1] : nil
    }

    // Loads run after the commit, so the old live player never swaps items before its layer hides; returns switch ms.
    @discardableResult
    func apply(_ effects: [Effect], for label: String, receivedAt start: TimeInterval) -> Double? {
        let loads = effects.filter(\.isLoad)
        withoutAnimation { perform(effects.filter { !$0.isLoad }) }
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
        switch base {
        case .black:
            window.showBase(clip: nil, logo: nil, breakScreen: false)
        case .logo(let number):
            window.showBase(clip: nil, logo: logo(number), breakScreen: false)
        case .clip(let slot):
            window.showBase(clip: slot, logo: nil, breakScreen: false)
        case .breakScreen(let item, _):
            breakTitle = item.text ?? defaultBreakTitle
            updateBreak()
            window.showBase(clip: nil, logo: nil, breakScreen: true)
            if item.countdown { startBreakTimer() }
        }
    }

    func setCover(_ cover: Cover?) {
        switch cover {
        case nil:
            window.showCover(logo: nil, black: false)
        case .black:
            window.showCover(logo: nil, black: true)
        case .logo(let number):
            let image = logo(number)
            window.showCover(logo: image, black: image == nil)
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

    fileprivate var isSwitch: Bool {
        switch self {
        case .show, .setCover: true
        default: false
        }
    }
}
