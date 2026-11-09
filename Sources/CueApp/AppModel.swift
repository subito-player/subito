import AVFoundation
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
    case confirmOutput(OutputChoice)
    case confirm(Notice)
    case noProjector
}

enum Problem: Equatable {
    case show(String)
    case keyMap(String)
}

private struct LoadedShow {
    var title: String?
    var cues: [Cue] = []
    var logos: [URL] = []
    var movieTitles: [String] = []
}

@MainActor
@Observable
final class AppModel {
    static let noticeSeconds: TimeInterval = 5
    static let tickSeconds: TimeInterval = 0.1

    let engine: PlaybackEngine
    let title: String?
    // Indexed by Cue.movieIndex.
    let movieTitles: [String]

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

    @ObservationIgnored var onOutputChange: () -> Void = {}
    @ObservationIgnored private(set) var quitConfirmed = false
    @ObservationIgnored private var noticeAt = Date.distantPast
    @ObservationIgnored private var outputPendingUntil = Date.distantPast
    @ObservationIgnored private var keyMap: KeyMap?
    @ObservationIgnored private var watcher: DisplayWatcher?
    @ObservationIgnored private var cursorGuard: CursorGuard?
    @ObservationIgnored private var timer: Timer?

    init(showPath: String?) {
        let lang = Lang.saved
        var problems: [Problem] = []
        var show = LoadedShow()
        if let showPath {
            do {
                show = try Self.loadShow(showPath)
            } catch {
                let name = URL(fileURLWithPath: showPath).lastPathComponent
                let reason = (error as? ShowError)?.description ?? "\(name): \(error.localizedDescription)"
                Log.info("error: \(reason)")
                problems.append(.show(reason))
            }
        }
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
        title = show.title
        movieTitles = show.movieTitles
        engine = PlaybackEngine(logos: show.logos, defaultBreakTitle: Strings(lang: lang).breakTitle)

        engine.onEvent = { [weak self] command in self?.send(command) }
        engine.onLoadError = { [weak self] _, url, message, warning in
            self?.loadFailed(LoadError(url: url, message: message, warning: warning))
        }
        watcher = DisplayWatcher(window: engine.window) { [weak self] status in self?.outputChanged(status) }
        cursorGuard = CursorGuard { [weak self] in self?.watcher?.outputDisplay }
        refreshDisplays()
        audioDevice = AudioOutput.defaultDeviceName()
        AudioOutput.observeDefaultDevice { [weak self] in self?.audioDevice = AudioOutput.defaultDeviceName() }

        // init(cues:) cannot return effects, so the first arm reaches the engine this way.
        run(state.replaceCues(show.cues), label: "open", receivedAt: ProcessInfo.processInfo.systemUptime)
        loadDurations(of: show.cues)
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

    private func loadDurations(of cues: [Cue]) {
        var seen = Set<URL>()
        for case .clip(_, let url) in cues.map(\.kind) where seen.insert(url).inserted {
            Task { [weak self] in
                guard let duration = try? await AVURLAsset(url: url).load(.duration), duration.seconds.isFinite,
                    let self, self.durations[url] == nil
                else { return }
                self.durations[url] = duration.seconds
            }
        }
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
            title: loaded.concert.title, cues: ShowLoader.flatten(loaded), logos: logos, movieTitles: movieTitles)
    }

    private static func movieShow(_ movie: Movie, at url: URL) -> LoadedShow {
        LoadedShow(title: movie.title, cues: ShowLoader.flatten(movie: movie, at: url), movieTitles: [movie.title])
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
