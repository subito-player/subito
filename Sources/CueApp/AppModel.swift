import AppKit
import CueCore
import Observation

enum KeyResult: Equatable {
    case command(Command)
    case advanced
    case nothing
}

struct LastKey: Equatable {
    var name: String
    var result: KeyResult
}

struct PlayTime: Equatable {
    var position: Double
    var duration: Double
}

struct LoadError: Equatable {
    var url: URL
    var message: String
    var warning: Bool
}

enum OutputChoice: Equatable {
    case automatic
    case display(CGDirectDisplayID)
}

enum Banner: Equatable {
    case focusLost
    case filePicker
    case confirmOutput(OutputChoice)
    case confirm(Notice)
    case noProjector
}

enum Problem: Equatable {
    case show(String)
    case keyMap(String)
}

// Shown from a crash relaunch until the first GO.
enum RecoveryNotice: Equatable {
    case recovered(index: Int?, position: Double)
    case skipped
}

enum ManualCheck: CaseIterable {
    case focus, updates, wallpaper, backup
}

private struct LoadedShow {
    var url: URL
    var title: String
    var cues: [Cue]
    var logos: [URL] = []
    var movieTitles: [String]
}

@MainActor
@Observable
final class AppModel {
    static let noticeSeconds: TimeInterval = 5
    static let tickSeconds: TimeInterval = 0.1

    let engine: PlaybackEngine
    private(set) var title: String?
    // Indexed by Cue.movieIndex.
    private(set) var movieTitles: [String] = []

    var lang: Lang {
        didSet {
            lang.save()
            engine.defaultBreakTitle = strings.breakTitle
            Log.info("language \(lang.rawValue)")
        }
    }
    var focusLost = false
    private(set) var state = ShowState()
    private(set) var lastKey: LastKey?
    private(set) var notice: Notice?
    private(set) var pending: Notice?
    private(set) var outputPending: OutputChoice?
    private(set) var problems: [Problem] = []
    private(set) var loadErrors: [LoadError] = []
    private(set) var durations: [URL: Double] = [:]
    private(set) var output: OutputStatus?
    private(set) var outputDisplay: CGDirectDisplayID?
    private(set) var displays: [DisplayChoice] = []
    private(set) var automaticOutput = true
    private(set) var audioDevice: String?
    private(set) var liveTime: PlayTime?
    private(set) var armedTime: PlayTime?
    private(set) var breakCountdown: String?
    private(set) var showFindings: [Finding] = []
    private(set) var systemFindings: [Finding] = []
    private(set) var checking = false
    private(set) var preflightOpen = false
    private(set) var recoveryNotice: RecoveryNotice?
    var manualChecks: Set<ManualCheck> = []
    var filePickerOpen = false

    @ObservationIgnored var onOutputChange: () -> Void = {}
    @ObservationIgnored private(set) var quitConfirmed = false
    @ObservationIgnored private var noticeAt = Date.distantPast
    @ObservationIgnored private var outputPendingUntil = Date.distantPast
    @ObservationIgnored private var keyMap: KeyMap?
    @ObservationIgnored private var watcher: DisplayWatcher?
    @ObservationIgnored private var cursorGuard: CursorGuard?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var showURL: URL?
    @ObservationIgnored private var showCheck: Task<Void, Never>?
    @ObservationIgnored private var stateSavedAt: TimeInterval = 0
    @ObservationIgnored private var launchPath: String?
    @ObservationIgnored private var recoveries: Int
    @ObservationIgnored private var refreshRates: [CGDirectDisplayID: [Double]] = [:]

    // recoveries: the consecutive recovered-launch count this launch writes until the first GO.
    init(plan: LaunchPlan, recoveries: Int) {
        let lang = Lang.saved
        var problems: [Problem] = []
        var keyMap: KeyMap?
        do {
            keyMap = try KeyMap(json: Data(KeyMap.defaultJSON.utf8))
        } catch {
            Log.info("error: \(error)")
            problems.append(.keyMap("\(error)"))
        }
        self.lang = lang
        self.keyMap = keyMap
        self.problems = problems
        self.recoveries = recoveries
        engine = PlaybackEngine(defaultBreakTitle: Strings(lang: lang).breakTitle)

        engine.onEvent = { [weak self] command in self?.send(command) }
        engine.onLoadError = { [weak self] _, url, message, warning in
            self?.loadFailed(LoadError(url: url, message: message, warning: warning))
        }
        watcher = DisplayWatcher(window: engine.window) { [weak self] status in self?.outputChanged(status) }
        cursorGuard = CursorGuard { [weak self] in self?.watcher?.outputDisplay }
        refreshDisplays()
        audioDevice = AudioOutput.defaultDeviceName()
        AudioOutput.observeDefaultDevice { [weak self] in
            self?.audioDevice = AudioOutput.defaultDeviceName()
            self?.checkSystem()
        }
        PreflightRunner.observePowerSource { [weak self] in self?.checkSystem() }

        start(plan)
        checkSystem()
        saveState()
        let timer = Timer(timeInterval: Self.tickSeconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Common mode keeps the clock running while a slider or menu is tracking the mouse.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    var strings: Strings {
        Strings(lang: lang)
    }

    var liveSlot: Slot? {
        if case .clip(let slot) = state.base { slot } else { nil }
    }

    var liveClip: Clip? {
        guard liveSlot != nil, let index = state.liveIndex, case .clip(let clip, _) = state.cues[index].kind else {
            return nil
        }
        return clip
    }

    // Pending confirmations outrank the no-projector banner because they last only 3 s.
    var banner: Banner? {
        if focusLost { return .focusLost }
        if filePickerOpen { return .filePicker }
        if let outputPending { return .confirmOutput(outputPending) }
        if let pending { return .confirm(pending) }
        return output == .missing ? .noProjector : nil
    }

    // A confirmation goes stale with its window, so it reaches the status line only while the banner hides it.
    var statusNotice: Notice? {
        guard let notice, notice.isConfirmation else { return notice }
        return pending == notice && banner != .confirm(notice) ? notice : nil
    }

    func name(of choice: OutputChoice, _ s: Strings) -> String {
        switch choice {
        case .automatic: s.automatic
        case .display(let id): s.display(displays.first { $0.id == id }?.name, id: id)
        }
    }

    var findings: [Finding] {
        showFindings + systemFindings
    }

    var blockedCues: Set<Int> {
        Set(showFindings.filter { $0.severity == .block }.compactMap(\.cueIndex))
    }

    // Clips the engine already reported stay out of the count, so one bad file is not announced twice.
    var blockedClipCount: Int {
        let reported = Set(loadErrors.filter { !$0.warning }.map(\.url))
        return blockedCues.filter { index in
            guard state.cues.indices.contains(index), case .clip(_, let url) = state.cues[index].kind else {
                return false
            }
            return !reported.contains(url)
        }.count
    }

    func cue(for url: URL) -> Cue? {
        state.cues.first { cue in
            if case .clip(_, let clipURL) = cue.kind { clipURL == url } else { false }
        }
    }

    func send(
        _ command: Command, chord: KeyChord? = nil,
        receivedAt: TimeInterval = ProcessInfo.processInfo.systemUptime
    ) {
        if !command.isEngineEvent { update(\.outputPending, nil) }
        if let chord {
            lastKey = LastKey(name: KeyInput.label(of: chord), result: .command(command))
            Log.deferred("key \(KeyInput.name(of: chord)) -> \(command)")
        }
        if case .armedReady(_, let url, let duration) = command, duration.isFinite, durations[url] != duration {
            durations[url] = duration
        }
        run(state.handle(command, now: Date()), label: "\(command)", receivedAt: receivedAt)
        if recoveryNotice != nil || recoveries > 0, state.liveIndex != nil {
            recoveryNotice = nil
            recoveries = 0
            saveState()
        }
    }

    // Replaces the cue list; the projector keeps whatever it shows until the next GO.
    @discardableResult
    func open(_ path: String) -> Bool {
        problems.removeAll { if case .show = $0 { true } else { false } }
        do {
            let show = try Self.loadShow(path)
            title = show.title
            movieTitles = show.movieTitles
            showURL = show.url
            recoveryNotice = nil
            loadErrors.removeAll()
            engine.setLogos(show.logos)
            Log.info("open \(show.url.path)")
            run(state.replaceCues(show.cues), label: "open", receivedAt: ProcessInfo.processInfo.systemUptime)
            checkShow(logos: show.logos)
            return true
        } catch {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let reason = (error as? ShowError)?.description ?? "\(name): \(error.localizedDescription)"
            Log.info("error: \(reason)")
            problems.append(.show(reason))
            return false
        }
    }

    func togglePreflight() {
        preflightOpen.toggle()
        if preflightOpen { checkSystem() }
    }

    func saveState(cleanExit: Bool = false) {
        stateSavedAt = ProcessInfo.processInfo.systemUptime
        // Until the launch's show opens, the file holds the only copy of what to recover.
        if showURL == nil, launchPath != nil { return }
        var liveIndex = state.liveIndex
        var position = liveIndex == nil ? nil : liveSlot.flatMap { engine.time($0)?.position }
        // Before the first GO after a recovery, the operator's latest park is what a second crash brings back.
        if liveIndex == nil, case .recovered(.some, _)? = recoveryNotice {
            liveIndex = state.armedIndex
            position = state.armedAt
        }
        let snapshot = RecoveryState(
            showPath: showURL?.path, mode: state.mode, liveIndex: liveIndex, livePosition: position,
            cover: state.cover, cleanExit: cleanExit, recoveries: cleanExit ? 0 : recoveries, savedAt: Date())
        if cleanExit {
            StateFile.saveNow(snapshot)
        } else {
            StateFile.save(snapshot)
        }
    }

    // Held keys must not repeat GO or seeks; every key is swallowed so nothing beeps on stage.
    func keyDown(_ event: NSEvent) -> NSEvent? {
        guard !event.isARepeat, let chord = KeyInput.chord(for: event) else { return nil }
        switch keyMap?.action(for: chord) {
        case .command(let command)?:
            send(command, chord: chord, receivedAt: event.timestamp)
        case .toggleAdvanced?:
            lastKey = LastKey(name: KeyInput.label(of: chord), result: .advanced)
        case nil:
            if chord.modifiers.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                return nil
            }
            lastKey = LastKey(name: KeyInput.label(of: chord), result: .nothing)
        }
        return nil
    }

    // Press twice within the confirm window, like every other choice that can change the projector.
    func pickOutput(_ choice: OutputChoice) {
        let current: OutputChoice? =
            automaticOutput ? .automatic : displays.first(where: \.saved).map { .display($0.id) }
        guard choice != current else { return }
        guard outputPending == choice, Date() < outputPendingUntil else {
            outputPending = choice
            outputPendingUntil = Date().addingTimeInterval(ShowState.confirmWindow)
            return
        }
        outputPending = nil
        let display: CGDirectDisplayID? =
            if case .display(let id) = choice { id } else { nil }
        Log.info("output display picked: \(display.map { "\($0)" } ?? "automatic")")
        watcher?.setPreferred(display)
        refreshDisplays()
    }

    private func run(_ effects: [Effect], label: String, receivedAt: TimeInterval) {
        for case .load(_, let url, _) in effects where loadErrors.contains(where: { $0.url == url }) {
            loadErrors.removeAll { $0.url == url }
        }
        engine.apply(effects, for: label, receivedAt: receivedAt)
        for case .notice(let notice) in effects {
            Log.deferred("notice: \(Strings(lang: .en).notice(notice))")
            self.notice = notice
            noticeAt = Date()
        }
        saveState()
        tick()
        if effects.contains(.quit) {
            quitConfirmed = true
            // Async because this can run inside applicationShouldTerminate.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func tick() {
        let now = Date()
        update(\.liveTime, liveSlot.flatMap(playTime))
        update(\.armedTime, state.armedSlot.flatMap(playTime))
        update(\.pending, state.activePending(at: now))
        if notice != nil, now.timeIntervalSince(noticeAt) >= Self.noticeSeconds { notice = nil }
        if outputPending != nil, now >= outputPendingUntil { outputPending = nil }
        var countdown: String?
        if case .breakScreen(let item, let startedAt) = state.base {
            countdown = PlaybackEngine.breakCountdown(item, startedAt: startedAt, now: now)
        }
        update(\.breakCountdown, countdown)
        if ProcessInfo.processInfo.systemUptime - stateSavedAt >= 1 { saveState() }
    }

    private func start(_ plan: LaunchPlan) {
        switch plan {
        case .empty:
            return
        case .open(let path):
            launchPath = path
            open(path)
        case .skipRecovery(let path, let mode):
            launchPath = path
            guard open(path) else { return }
            state.restoreMode(mode)
            recoveryNotice = .skipped
            Log.info("recovery skipped after \(recoveries) recovered launches crashed: \(path), mode \(mode)")
        case .recover(let path, let mode, let index, let position):
            launchPath = path
            guard open(path) else { return }
            state.restoreMode(mode)
            let armed = index.flatMap { state.cues.indices.contains($0) ? $0 : nil }
            recoveryNotice = .recovered(index: armed, position: position)
            Log.info("recovered \(path): mode \(mode), arming \(armed.map(String.init) ?? "nothing") at \(position)")
            guard let armed else { return }
            let now = Date()
            let effects = state.handle(.arm(index: armed), now: now) + state.handle(.parkArmedAt(position), now: now)
            run(effects, label: "recover", receivedAt: ProcessInfo.processInfo.systemUptime)
        }
    }

    // Probes run off the main thread; a newer show cancels the older check.
    private func checkShow(logos: [URL]) {
        showCheck?.cancel()
        let cues = state.cues
        let urls = Set(cues.compactMap { cue -> URL? in if case .clip(_, let url) = cue.kind { url } else { nil } })
        let logoFindings = logos.indices.compactMap { index -> Finding? in
            guard engine.logo(index + 1) == nil else { return nil }
            return Finding(severity: .warn, kind: .logo, detail: "\(index + 1) · \(logos[index].lastPathComponent)")
        }
        showFindings = []
        checking = true
        showCheck = Task { [weak self] in
            var probes: [URL: ClipProbe] = [:]
            await withTaskGroup(of: (URL, ClipProbe).self) { group in
                for url in urls {
                    group.addTask { (url, await PreflightRunner.probe(url)) }
                }
                for await (url, probe) in group {
                    probes[url] = probe
                    self?.noteDuration(url, probe.duration)
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.showChecked(Preflight.evaluate(cues: cues, probes: probes) + logoFindings, probes: probes)
        }
    }

    private func showChecked(_ findings: [Finding], probes: [URL: ClipProbe]) {
        for (url, probe) in probes.sorted(by: { $0.key.path < $1.key.path }) {
            Log.deferred(
                "probe \(url.lastPathComponent): exists \(probe.exists), playable \(probe.playable), "
                    + "\(probe.width)x\(probe.height), \(probe.fps) fps, \(probe.codec), \(probe.duration) s, "
                    + "video \(probe.hasVideo), audio \(probe.hasAudio)")
        }
        for finding in findings {
            let cue = finding.cueIndex.map(String.init) ?? "-"
            Log.deferred("preflight \(finding.severity) cue \(cue) \(finding.kind): \(finding.detail)")
        }
        let blocks = findings.filter { $0.severity == .block }.count
        let warnings = findings.filter { $0.severity == .warn }.count
        Log.info("preflight show: \(probes.count) files, \(blocks) blocking, \(warnings) warnings")
        showFindings = findings
        checking = false
    }

    private func checkSystem() {
        let rates = outputDisplay.map(rates(of:)) ?? []
        let probe = PreflightRunner.system(output: output, availableHz: rates, soundDevice: audioDevice)
        let findings = Preflight.evaluate(system: probe)
        guard findings != systemFindings else { return }
        systemFindings = findings
        let summary = findings.map { "\($0.kind) \($0.severity)\($0.detail.isEmpty ? "" : " \($0.detail)")" }
        Log.info("preflight system: \(summary.joined(separator: "; "))")
    }

    // Mode lists only change with a display reconfiguration, which clears the cache.
    private func rates(of display: CGDirectDisplayID) -> [Double] {
        if let cached = refreshRates[display] { return cached }
        let rates = PreflightRunner.refreshRates(of: display)
        refreshRates[display] = rates
        return rates
    }

    private func noteDuration(_ url: URL, _ duration: Double) {
        if duration.isFinite, duration > 0, durations[url] == nil { durations[url] = duration }
    }

    // Observation fires on every set, so unchanged values are skipped to keep the 10 Hz tick cheap.
    private func update<Value: Equatable>(_ path: ReferenceWritableKeyPath<AppModel, Value>, _ value: Value) {
        if self[keyPath: path] != value { self[keyPath: path] = value }
    }

    private func playTime(_ slot: Slot) -> PlayTime? {
        engine.time(slot).map { PlayTime(position: $0.position, duration: $0.duration) }
    }

    private func outputChanged(_ status: OutputStatus) {
        update(\.output, status)
        if case .attached = status { cursorGuard?.keepOffOutput() }
        refreshDisplays()
        refreshRates = [:]
        // The watcher's first report arrives from its own init; init checks once everything is set up.
        if watcher != nil { checkSystem() }
        onOutputChange()
    }

    private func refreshDisplays() {
        update(\.outputDisplay, watcher?.outputDisplay)
        update(\.displays, DisplayWatcher.choices())
        update(\.automaticOutput, !DisplayWatcher.hasSavedChoice)
    }

    private func loadFailed(_ error: LoadError) {
        loadErrors.removeAll { $0.url == error.url }
        loadErrors.append(error)
    }

    private static func loadShow(_ path: String) throws -> LoadedShow {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
            let movieURL = try ShowLoader.importFolder(url)
            return movieShow(try ShowLoader.loadMovie(at: movieURL), at: movieURL)
        }
        guard url.lastPathComponent.hasSuffix(".concert.json") else {
            return movieShow(try ShowLoader.loadMovie(at: url), at: url)
        }
        let loaded = try ShowLoader.loadConcert(at: url)
        // Loop logos fail as images and so count as missing, keeping logo numbers aligned.
        let logos = loaded.concert.logos.map { logo in
            switch logo {
            case .image(let path), .loop(let path): ShowLoader.resolve(path, relativeTo: url)
            }
        }
        let movieTitles = loaded.concert.items.compactMap { item -> String? in
            guard case .movie(let ref) = item else { return nil }
            return loaded.movies[ShowLoader.resolve(ref.file, relativeTo: url)]?.title ?? ref.file
        }
        return LoadedShow(
            url: url, title: loaded.concert.title, cues: ShowLoader.flatten(loaded), logos: logos,
            movieTitles: movieTitles)
    }

    private static func movieShow(_ movie: Movie, at url: URL) -> LoadedShow {
        LoadedShow(
            url: url, title: movie.title, cues: ShowLoader.flatten(movie: movie, at: url), movieTitles: [movie.title])
    }
}

extension Command {
    fileprivate var isEngineEvent: Bool {
        switch self {
        case .armedReady, .liveEnded: true
        default: false
        }
    }
}

extension Notice {
    fileprivate var isConfirmation: Bool {
        switch self {
        case .confirmUnmute, .confirmMode, .confirmQuit: true
        default: false
        }
    }
}
