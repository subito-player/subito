import AppKit
import CueCore
import Observation
import UniformTypeIdentifiers

enum KeyResult: Equatable {
    case command(Command)
    case advanced
    case stressStopped
    case nothing
}

struct LastKey: Equatable {
    var chord: KeyChord
    var result: KeyResult
}

struct PlayTime: Equatable {
    var position: Double
    var duration: Double
}

struct LoadError: Equatable {
    var url: URL
    var failure: LoadFailure

    var warning: Bool {
        failure == .pictureUnconfirmed
    }
}

enum OutputChoice: Equatable {
    case automatic
    case display(CGDirectDisplayID)
}

enum Banner: Equatable {
    case focusLost
    case filePicker
    case typing
    case confirmOutput(OutputChoice)
    case confirmPresentation(OutputPresentation)
    case confirmDelete(Place)
    case confirm(Notice)
    case noProjector
}

// Only file names and numbers ride along, so Strings can say it in the operator's language.
enum Problem: Equatable {
    // error nil: not a show-format problem, e.g. the file system refused.
    case show(file: String, error: ShowError?)
    case keyMap(KeyMapError)
    case save(file: String, reason: String)
}

// Editor messages for the status line; they fade like notices.
enum EditNotice: Error, Equatable {
    case refused(EditRefusal)
    case selectMovie
    case emptyTitle
    case invalidTime
    case invalidMinutes
    case cannotAddMovie(file: String, error: ShowError?)
    case concertAsMovie
    case convertWhileRunning
    case convertFailed(file: String, Conversion.Failure)
}

// An inspector field; its place pins a draft to one item, so it never lands on another.
enum Field: Hashable {
    case showTitle
    case movieTitle(URL)
    case clipTitle(Place)
    case brief(Place)
    case plannedEnd(Place)
    case tail(Place)
    case breakText(Place)
    case breakMinutes(Place)
}

// Shown from a crash relaunch until the first GO.
enum RecoveryNotice: Equatable {
    case recovered(index: Int?, position: Double)
    case skipped
}

enum ManualCheck: CaseIterable {
    case focus, updates, wallpaper, backup
}

@MainActor
@Observable
final class AppModel {
    static let noticeSeconds: TimeInterval = 5
    static let tickSeconds: TimeInterval = 0.1
    static let keyMapFile = AppInfo.supportDirectory.appendingPathComponent("keymap.json")
    static let cheatSheetFile = AppInfo.supportDirectory.appendingPathComponent("cheatsheet.html")

    let engine: PlaybackEngine
    let keyMap: KeyMap
    let advanced = Advanced()
    let converter = Converter()
    private(set) var document: ShowDocument?

    var lang: Lang {
        didSet {
            lang.save()
            engine.defaultBreakTitle = strings.breakTitle
            engine.window.title = strings.outputWindowTitle(AppInfo.name)
            onLanguageChange()
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
    // Never saved, so every launch, crash recovery included, starts fullscreen.
    private(set) var presentation = OutputPresentation.fullscreen
    private(set) var presentationPending: OutputPresentation?
    private(set) var audioDevice: String?
    private(set) var liveTime: PlayTime?
    private(set) var armedTime: PlayTime?
    private(set) var breakCountdown: String?
    private(set) var showFindings: [Finding] = []
    private(set) var systemFindings: [Finding] = []
    private(set) var checking = false
    private(set) var preflightOpen = false
    private(set) var keysOpen = false
    private(set) var recoveryNotice: RecoveryNotice?
    var manualChecks: Set<ManualCheck> = []
    var filePickerOpen = false
    // Set by the control window while a text field has the keyboard.
    var typing = false
    private(set) var editing = false
    private(set) var selection: Place?
    private(set) var deletePending: Place?
    private(set) var editNotice: EditNotice?
    private(set) var drafts: [Field: String] = [:]

    @ObservationIgnored var onOutputChange: () -> Void = {}
    @ObservationIgnored var onModeChange: (Mode) -> Void = { _ in }
    @ObservationIgnored var onLanguageChange: () -> Void = {}
    @ObservationIgnored private var appliedMode = Mode.rehearsal
    @ObservationIgnored private var appliedUnlock = false
    @ObservationIgnored private var deletePendingUntil = Date.distantPast
    @ObservationIgnored private var editNoticeAt = Date.distantPast
    @ObservationIgnored private var focusedField: Field?
    // Esc'd until focused again, so the field's own end-of-editing write cannot bring the text back.
    @ObservationIgnored private var cancelledField: Field?
    @ObservationIgnored private var dragged: (place: Place, token: String)?
    @ObservationIgnored private var probes: [URL: ClipProbe] = [:]
    @ObservationIgnored private(set) var quitConfirmed = false
    @ObservationIgnored private var noticeAt = Date.distantPast
    @ObservationIgnored private var outputPendingUntil = Date.distantPast
    @ObservationIgnored private var presentationPendingUntil = Date.distantPast
    @ObservationIgnored private var watcher: DisplayWatcher?
    @ObservationIgnored private var cursorGuard: CursorGuard?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var showCheck: Task<Void, Never>?
    @ObservationIgnored private var stateSavedAt: TimeInterval = 0
    @ObservationIgnored private var launchPath: String?
    @ObservationIgnored private var recoveries: Int
    @ObservationIgnored private var refreshRates: [CGDirectDisplayID: [Double]] = [:]

    // recoveries: the consecutive recovered-launch count this launch writes until the first GO.
    init(plan: LaunchPlan, recoveries: Int, mode: Mode) {
        let lang = Lang.saved
        var problems: [Problem] = []
        let (keyMap, keyMapError) = Self.loadKeyMap()
        if let keyMapError { problems.append(.keyMap(keyMapError)) }
        self.lang = lang
        self.keyMap = keyMap
        self.problems = problems
        self.recoveries = recoveries
        engine = PlaybackEngine(defaultBreakTitle: Strings(lang: lang).breakTitle)
        engine.window.title = Strings(lang: lang).outputWindowTitle(AppInfo.name)

        engine.onEvent = { [weak self] command in self?.send(command) }
        advanced.send = { [weak self] command in self?.send(command) }
        advanced.mode = { [weak self] in self?.state.mode ?? .concert }
        converter.onConverted = { [weak self] source, output in self?.converted(source, to: output) }
        converter.onFailed = { [weak self] source, failure in
            self?.showEditNotice(.convertFailed(file: source.lastPathComponent, failure))
        }
        engine.onLoadError = { [weak self] _, url, failure in
            self?.loadFailed(LoadError(url: url, failure: failure))
        }
        watcher = DisplayWatcher(window: engine.window) { [weak self] status in self?.outputChanged(status) }
        // Only a fullscreen output owns its display; a windowed or hidden one leaves it to the cursor.
        cursorGuard = CursorGuard { [weak self] in
            guard let self, self.engine.window.presentation == .fullscreen else { return nil }
            return self.watcher?.outputDisplay
        }
        refreshDisplays()
        audioDevice = AudioOutput.defaultDeviceName()
        AudioOutput.observeDefaultDevice { [weak self] in
            self?.audioDevice = AudioOutput.defaultDeviceName()
            self?.checkSystem()
        }
        PreflightRunner.observePowerSource { [weak self] in self?.checkSystem() }

        state.restoreMode(mode)
        appliedMode = mode
        Log.info("mode \(mode.rawValue)")
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
        Strings(lang: lang, keyMap: keyMap)
    }

    var title: String? {
        document?.title
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
        // The concert quit's last step is a click, so nothing may hide its target.
        if pending == .confirmQuitClick { return .confirm(.confirmQuitClick) }
        if filePickerOpen { return .filePicker }
        if typing { return .typing }
        if let outputPending { return .confirmOutput(outputPending) }
        if let presentationPending { return .confirmPresentation(presentationPending) }
        if let deletePending { return .confirmDelete(deletePending) }
        if let pending { return .confirm(pending) }
        return output == .missing ? .noProjector : nil
    }

    // A confirmation goes stale with its window, so it reaches the status line only while the banner hides it.
    var statusNotice: Notice? {
        guard let notice, notice.isConfirmation else { return notice }
        // "Click here" is only true on the banner itself.
        guard notice != .confirmQuitClick else { return nil }
        return pending == notice && banner != .confirm(notice) ? notice : nil
    }

    var effectivePresentation: OutputPresentation {
        .effective(requested: presentation, mode: state.mode)
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
        if !command.isEngineEvent {
            update(\.outputPending, nil)
            update(\.presentationPending, nil)
            update(\.deletePending, nil)
        }
        if let chord {
            lastKey = LastKey(chord: chord, result: .command(command))
            Log.deferred("key \(chord.name) -> \(command)")
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
            let document = try ShowDocument.load(URL(fileURLWithPath: path).standardizedFileURL)
            // Conversions belong to the show they were started in.
            converter.cancelAll(reason: "show opened")
            converter.sweep(
                document.cues.compactMap { cue in if case .clip(_, let url) = cue.kind { url } else { nil } })
            self.document = document
            problems.removeAll { if case .save = $0 { true } else { false } }
            recoveryNotice = nil
            loadErrors.removeAll()
            selection = nil
            deletePending = nil
            dragged = nil
            drafts = [:]
            focusedField = nil
            engine.setLogos(document.logos)
            Log.info("open \(document.url.path)")
            run(state.replaceCues(document.cues), label: "open", receivedAt: ProcessInfo.processInfo.systemUptime)
            probes = [:]
            checkShow()
            return true
        } catch {
            let name = URL(fileURLWithPath: path).lastPathComponent
            let reason = (error as? ShowError)?.description ?? "\(name): \(error.localizedDescription)"
            Log.info("error: \(reason)")
            problems.append(.show(file: name, error: error as? ShowError))
            return false
        }
    }

    func togglePreflight() {
        preflightOpen.toggle()
        guard preflightOpen else { return }
        checkSystem()
        converter.locate()
    }

    func toggleKeys() {
        keysOpen.toggle()
    }

    func saveState(cleanExit: Bool = false) {
        stateSavedAt = ProcessInfo.processInfo.systemUptime
        // Until the launch's show opens, the file holds the only copy of what to recover.
        if document == nil, launchPath != nil { return }
        var liveIndex = state.liveIndex
        var position = liveIndex == nil ? nil : liveSlot.flatMap { engine.time($0)?.position }
        // Before the first GO after a recovery, the operator's latest park is what a second crash brings back.
        if liveIndex == nil, case .recovered(.some, _)? = recoveryNotice {
            liveIndex = state.armedIndex
            position = state.armedAt
        }
        let snapshot = RecoveryState(
            showPath: document?.url.path, mode: state.mode, liveIndex: liveIndex, livePosition: position,
            cover: state.cover, cleanExit: cleanExit, recoveries: cleanExit ? 0 : recoveries, savedAt: Date())
        if cleanExit {
            StateFile.saveNow(snapshot)
        } else {
            StateFile.save(snapshot)
        }
    }

    // Held keys must not repeat GO or seeks; every key is swallowed so nothing beeps on stage.
    func keyDown(_ event: NSEvent) -> NSEvent? {
        guard !event.isARepeat else { return nil }
        let chord = KeyInput.chord(for: event)
        // The key that stops a stress run does nothing else, so stopping never switches the projector.
        if advanced.stressRunning {
            advanced.stopStress(reason: "key \(chord?.name ?? "code \(event.keyCode)")")
            if let chord { lastKey = LastKey(chord: chord, result: .stressStopped) }
            return nil
        }
        guard let chord else { return nil }
        switch keyMap.action(for: chord) {
        case .command(let command)?:
            send(command, chord: chord, receivedAt: event.timestamp)
        case .toggleAdvanced?:
            lastKey = LastKey(chord: chord, result: .advanced)
            advanced.toggle()
        case nil:
            if chord.modifiers.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                return nil
            }
            lastKey = LastKey(chord: chord, result: .nothing)
        }
        return nil
    }

    // Press twice within the confirm window, like every other choice that can change the projector.
    func pickOutput(_ choice: OutputChoice) {
        advanced.stopStress(reason: "output picker click")
        guard state.mode == .rehearsal else { return }
        let current: OutputChoice? =
            automaticOutput ? .automatic : displays.first(where: \.saved).map { .display($0.id) }
        guard choice != current else { return }
        presentationPending = nil
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

    // Rehearsal debugging; confirmed like the display chips because it changes the projector.
    func pickPresentation(_ presentation: OutputPresentation) {
        advanced.stopStress(reason: "view click")
        guard state.mode == .rehearsal, presentation != self.presentation else { return }
        outputPending = nil
        guard presentationPending == presentation, Date() < presentationPendingUntil else {
            presentationPending = presentation
            presentationPendingUntil = Date().addingTimeInterval(ShowState.confirmWindow)
            return
        }
        presentationPending = nil
        self.presentation = presentation
        applyPresentation(reason: "picked")
    }

    private func applyPresentation(reason: String) {
        let effective = effectivePresentation
        guard effective != engine.window.presentation else { return }
        Log.info("output presentation \(engine.window.presentation) -> \(effective) (\(reason))")
        engine.window.present(effective)
        // After the window is borderless and shielding again, so the watcher puts it back on the output display.
        watcher?.placesWindow = effective == .fullscreen
        if effective == .fullscreen { cursorGuard?.keepOffOutput() }
    }

    // --- Advanced view ---

    // Regenerated from the loaded key map on every click, so a remapped key always prints as it works.
    func openCheatSheet() {
        guard state.mode == .rehearsal else { return }
        let file = Self.cheatSheetFile
        let name = file.lastPathComponent
        problems.removeAll { if case .save(name, _) = $0 { true } else { false } }
        do {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(CheatSheet.html(keyMap: keyMap, lang: lang).utf8).write(to: file, options: .atomic)
            Log.info("cheat sheet written: \(file.path)")
            NSWorkspace.shared.open(file)
        } catch {
            Log.info("error: cannot write \(file.path): \(error.localizedDescription)")
            problems.append(.save(file: name, reason: error.localizedDescription))
        }
    }

    func revealKeyMap() {
        guard state.mode == .rehearsal else { return }
        NSWorkspace.shared.activateFileViewerSelecting([Self.keyMapFile])
    }

    func openLogFolder() {
        guard state.mode == .rehearsal else { return }
        NSWorkspace.shared.open(Log.directory)
    }

    // The owner edits keymap.json; a broken one never takes the show keys away.
    private static func loadKeyMap() -> (KeyMap, KeyMapError?) {
        let url = keyMapFile
        do {
            if try KeyMap.installDefault(at: url) { Log.info("keymap: default written to \(url.path)") }
        } catch {
            Log.info("error: cannot write the default keymap \(url.path): \(error.localizedDescription)")
        }
        let (map, error) = KeyMap.load(from: url)
        if let error {
            Log.info("error: \(error), using the default keys")
        } else {
            Log.info("keymap \(url.path)")
        }
        return (map, error)
    }

    // --- Converter ---

    var convertible: [URL] {
        Conversion.candidates(cues: state.cues, findings: showFindings)
    }

    // Rehearsal only, and never started while a clip is live and running; a GO once it runs is fine.
    func convert(_ urls: [URL]) {
        guard state.mode == .rehearsal, !urls.isEmpty else { return }
        guard !state.liveClipRunning else {
            Log.info("convert refused: a live clip is running")
            return showEditNotice(.convertWhileRunning)
        }
        converter.enqueue(urls)
    }

    func cancelConversion(_ url: URL) {
        converter.cancel(url)
    }

    func cancelConversions() {
        converter.cancelAll(reason: "cancel all click")
    }

    // Every item playing the source switches to the new file; the original stays on disk.
    private func converted(_ source: URL, to output: URL) {
        guard let document else { return }
        var places: [Place] = []
        for row in document.rows {
            guard case .cue(let index) = row.kind, case .clip(_, let url) = document.cues[index].kind, url == source,
                let place = row.place, !places.contains(place)
            else { continue }
            places.append(place)
        }
        Log.info("converted \(source.lastPathComponent) -> \(output.lastPathComponent), \(places.count) items updated")
        // A file once probed under that name (since deleted, say) is judged afresh.
        probes[output] = nil
        durations[output] = nil
        for place in places { perform(.replaceClipFile(place, output)) }
    }

    // --- Modes and editor ---

    var canEdit: Bool {
        state.canEdit
    }

    var rows: [Row] {
        document?.rows ?? []
    }

    var selectedRow: Row? {
        selection.flatMap { place in rows.first { $0.place == place } }
    }

    func isLocked(_ place: Place) -> Bool {
        document?.isLocked(place, live: state.liveIndex) ?? false
    }

    // Confirm-type clicks stop a stress run first, or its next random key would cancel the confirmation.
    func requestMode(_ mode: Mode) {
        advanced.stopStress(reason: "mode click")
        commitDrafts()
        send(.requestMode(mode))
    }

    func unlockEditing() {
        advanced.stopStress(reason: "unlock click")
        send(.unlockEditing)
    }

    func lockEditing() {
        advanced.stopStress(reason: "lock click")
        commitDrafts()
        send(.lockEditing)
    }

    func confirmQuitByClick() {
        advanced.stopStress(reason: "quit click")
        send(.confirmQuitByClick)
    }

    func toggleEditing() {
        commitDrafts()
        editing = !editing && canEdit && document != nil
        if !editing {
            selection = nil
            deletePending = nil
        }
    }

    func select(_ place: Place?) {
        guard selection != place else { return }
        commitDrafts()
        selection = place
    }

    // Press twice within the confirm window; a delete cannot be undone.
    func requestDelete(_ place: Place) {
        advanced.stopStress(reason: "delete click")
        let now = Date()
        guard deletePending == place, now < deletePendingUntil else {
            deletePending = place
            deletePendingUntil = now.addingTimeInterval(ShowState.confirmWindow)
            return
        }
        deletePending = nil
        edit(.delete(place))
    }

    // The token tells our own row drags from text dragged in from other apps.
    func startDrag(_ place: Place) -> String {
        let token = "row-" + UUID().uuidString
        dragged = (place, token)
        Log.deferred("drag start \(place.file.lastPathComponent)#\(place.index)")
        return token
    }

    // An ignored drop keeps the drag, because AppKit may reuse the same token when the row is dragged again.
    func drop(token: String, onto row: Row) {
        guard let dragged, dragged.token == token else {
            Log.deferred("drop ignored: token mismatch (dragging: \(self.dragged != nil))")
            return
        }
        guard let target = document?.dropPlace(moving: dragged.place, onto: row), target != dragged.place else {
            let onto = row.place.map { "\($0.file.lastPathComponent)#\($0.index)" } ?? "header"
            Log.deferred("drop ignored: \(dragged.place.file.lastPathComponent)#\(dragged.place.index) onto \(onto)")
            return
        }
        edit(.move(dragged.place, to: target.index))
    }

    func add(_ item: Item) {
        guard let place = document?.insertionPlace(for: .item, selected: selection) else { return }
        edit(.insert(item, at: place))
    }

    // File-name order, so NN_ prefixes keep their sequence whatever order the picker or Finder reports.
    func addClips(_ urls: [URL]) {
        let clips = urls.filter(Self.isVideo).sorted {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        guard canEdit, !clips.isEmpty, let document else { return }
        guard let place = document.insertionPlace(for: .clip, selected: selection) else {
            return showEditNotice(.selectMovie)
        }
        edit(.insertClips(clips, at: place))
    }

    // Finder drops: videos become clips, a movie file or clip folder becomes a movie.
    func addFiles(_ urls: [URL]) {
        var clips: [URL] = []
        for url in urls {
            var isFolder: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder)
            switch DroppedFile.classify(url, isFolder: isFolder.boolValue, isVideo: Self.isVideo(url)) {
            case .clip: clips.append(url)
            case .movie: addMovie(url)
            case .none: Log.deferred("drop ignored: \(url.lastPathComponent)")
            }
        }
        addClips(clips)
    }

    func addMovie(_ url: URL) {
        guard canEdit, let document else { return }
        guard let place = document.insertionPlace(for: .movie, selected: selection) else {
            return showEditNotice(.refused(.movieInMovie))
        }
        // A concert used as a movie would stop its own concert from loading.
        guard !url.lastPathComponent.hasSuffix(".concert.json") else {
            return showEditNotice(.concertAsMovie)
        }
        do {
            let (file, movie) = try ShowLoader.openMovie(url.standardizedFileURL)
            edit(.insertMovie(movie, file, at: place.index))
        } catch {
            let reason = (error as? ShowError)?.description ?? error.localizedDescription
            Log.info("error: cannot add movie \(url.path): \(reason)")
            showEditNotice(.cannotAddMovie(file: url.lastPathComponent, error: error as? ShowError))
        }
    }

    // Rehearsal only, like Open: an unlocked concert edits the show it has, never swaps it.
    func createConcert(at url: URL) {
        guard state.mode == .rehearsal else { return }
        do {
            // A new concert is empty, so it opens ready to edit.
            if open(try ShowLoader.createConcert(at: url.standardizedFileURL).path), !editing { toggleEditing() }
        } catch {
            Log.info("error: cannot create \(url.path): \(error.localizedDescription)")
            problems.append(.save(file: url.lastPathComponent, reason: error.localizedDescription))
        }
    }

    // A video becomes a loop, anything else an image.
    func setLogoFile(_ number: Int, _ url: URL?) {
        edit(.setLogoFile(number, url.map { Self.isVideo($0) ? .loop($0.path) : .image($0.path) }))
    }

    func setCountdown(_ place: Place, _ on: Bool) {
        commitDrafts()
        guard let item = breakItem(at: place) else { return }
        perform(.setBreak(place, minutes: item.minutes, countdown: on))
    }

    func edit(_ op: Edit) {
        commitDrafts()
        // Places shift with every edit, so an older drag must never move anything.
        dragged = nil
        perform(op)
    }

    func draft(_ field: Field) -> String {
        drafts[field] ?? value(of: field)
    }

    func setDraft(_ field: Field, _ text: String) {
        if field != cancelledField, drafts[field] != text { drafts[field] = text }
    }

    func focusChanged(_ field: Field, focused: Bool) {
        if focused {
            focusedField = field
            cancelledField = nil
            return
        }
        if focusedField == field { focusedField = nil }
        commit(field)
    }

    // Esc: the field goes back to the saved value.
    func cancelTyping() {
        guard let focusedField else { return }
        drafts[focusedField] = nil
        cancelledField = focusedField
    }

    // Before any other edit, so a draft pinned to a place never outlives the items around it.
    func commitDrafts() {
        for field in drafts.keys { commit(field) }
    }

    func commit(_ field: Field) {
        guard let text = drafts.removeValue(forKey: field), text != value(of: field) else { return }
        switch change(field, to: text) {
        case .success(let op): perform(op)
        case .failure(let notice): showEditNotice(notice)
        }
    }

    static func isVideo(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .movie) ?? false
    }

    private func perform(_ op: Edit) {
        guard canEdit, let document else { return }
        switch document.apply(op, live: state.liveIndex) {
        case .failure(let refusal):
            Log.info("edit refused (\(refusal)): \(Self.describe(op))")
            showEditNotice(.refused(refusal))
        case .success(let result):
            Log.info("edit \(Self.describe(op))")
            self.document = result.document
            if result.document.logos != document.logos { engine.setLogos(result.document.logos) }
            // A picked file is probed again, so a re-exported loop is not judged by its old probe.
            let logos = result.document.logos
            if case .setLogoFile(let number, _?) = op, logos.indices.contains(number - 1),
                let picked = logos[number - 1]
            {
                probes[picked.url] = nil
                durations[picked.url] = nil
            }
            // Items may have shifted: a pending delete must never land on another item.
            deletePending = nil
            switch op {
            case .delete: selection = nil
            case .insert, .insertClips, .insertMovie, .move: selection = result.touched
            default: break
            }
            for file in result.changed { write(file, of: result.document) }
            if case .recovered(let index?, let position)? = recoveryNotice {
                let map = result.indexMap
                recoveryNotice = .recovered(index: map.indices.contains(index) ? map[index] : nil, position: position)
            }
            let effects = state.applyEdit(cues: result.document.cues, indexMap: result.indexMap)
            run(effects, label: "edit", receivedAt: ProcessInfo.processInfo.systemUptime)
            let urls = Set(
                state.cues.compactMap { cue -> URL? in if case .clip(_, let url) = cue.kind { url } else { nil } })
            loadErrors.removeAll { !urls.contains($0.url) }
            // An added clip is probed again, so a fixed or re-exported file is not judged by its old probe.
            let kept = Set(result.indexMap.compactMap { $0 })
            for (index, cue) in state.cues.enumerated() where !kept.contains(index) {
                if case .clip(_, let url) = cue.kind {
                    probes[url] = nil
                    durations[url] = nil
                }
            }
            checkShow()
        }
    }

    // The in-memory show keeps the change either way; the status line says the file is behind.
    private func write(_ file: URL, of document: ShowDocument) {
        let name = file.lastPathComponent
        problems.removeAll { if case .save(name, _) = $0 { true } else { false } }
        do {
            try document.save(file)
        } catch {
            Log.info("error: cannot save \(file.path): \(error.localizedDescription)")
            problems.append(.save(file: name, reason: error.localizedDescription))
        }
    }

    private func value(of field: Field) -> String {
        switch field {
        case .showTitle: document?.title ?? ""
        case .movieTitle(let url): document?.movies[url]?.title ?? ""
        case .clipTitle(let place): clip(at: place)?.title ?? ""
        case .brief(let place): clip(at: place)?.brief ?? ""
        case .plannedEnd(let place): clip(at: place)?.plannedEndS.map(Clock.text) ?? ""
        case .tail(let place): clip(at: place)?.tailS.map(Clock.text) ?? ""
        case .breakText(let place): breakItem(at: place)?.text ?? ""
        case .breakMinutes(let place): breakItem(at: place).map { String(format: "%g", $0.minutes) } ?? ""
        }
    }

    private func change(_ field: Field, to text: String) -> Result<Edit, EditNotice> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch field {
        case .showTitle:
            guard let document, !trimmed.isEmpty else { return .failure(.emptyTitle) }
            return .success(document.concert == nil ? .renameMovie(document.url, trimmed) : .renameConcert(trimmed))
        case .movieTitle(let url):
            return trimmed.isEmpty ? .failure(.emptyTitle) : .success(.renameMovie(url, trimmed))
        case .clipTitle(let place):
            return .success(.renameClip(place, trimmed))
        case .brief(let place):
            return .success(.setBrief(place, trimmed))
        case .breakText(let place):
            return .success(.setBreakText(place, trimmed))
        case .plannedEnd(let place), .tail(let place):
            guard let clip = clip(at: place) else { return .failure(.refused(.noSuchItem)) }
            let seconds = trimmed.isEmpty ? nil : Clock.seconds(from: trimmed)
            guard trimmed.isEmpty || seconds != nil else { return .failure(.invalidTime) }
            if case .tail = field {
                return .success(.setClipTimes(place, plannedEndS: clip.plannedEndS, tailS: seconds))
            }
            return .success(.setClipTimes(place, plannedEndS: seconds, tailS: clip.tailS))
        case .breakMinutes(let place):
            guard let item = breakItem(at: place) else { return .failure(.refused(.noSuchItem)) }
            let minutes = Double(trimmed.replacingOccurrences(of: ",", with: "."))
            guard let minutes, minutes.isFinite, minutes >= 0 else { return .failure(.invalidMinutes) }
            return .success(.setBreak(place, minutes: minutes, countdown: item.countdown))
        }
    }

    private func clip(at place: Place) -> Clip? {
        if case .clip(let clip)? = document?.item(at: place) { clip } else { nil }
    }

    private func breakItem(at place: Place) -> BreakItem? {
        if case .breakScreen(let item)? = document?.item(at: place) { item } else { nil }
    }

    private func showEditNotice(_ notice: EditNotice) {
        Log.deferred("edit notice: \(Strings(lang: .en, keyMap: keyMap).editNotice(notice))")
        editNotice = notice
        editNoticeAt = Date()
    }

    // Concert hides the rest of the Mac and locks the editor; an unlock opens only the editor.
    private func syncMode() {
        if state.mode != appliedMode {
            appliedMode = state.mode
            advanced.stopStress(reason: "mode changed")
            Log.info("mode \(state.mode.rawValue)")
            if state.mode == .concert {
                presentation = .fullscreen
                converter.cancelAll(reason: "concert mode")
            }
            applyPresentation(reason: "mode \(state.mode.rawValue)")
            onModeChange(state.mode)
        }
        if state.editUnlocked != appliedUnlock {
            appliedUnlock = state.editUnlocked
            Log.info(appliedUnlock ? "editing unlocked" : "editing locked")
        }
        guard !state.canEdit, editing || selection != nil || !drafts.isEmpty else { return }
        editing = false
        selection = nil
        deletePending = nil
        drafts = [:]
    }

    private static func describe(_ op: Edit) -> String {
        guard case .insertMovie(let movie, let file, let index) = op else { return "\(op)" }
        return "insertMovie(\(movie.title), \(file.path), at: \(index))"
    }

    private func run(_ effects: [Effect], label: String, receivedAt: TimeInterval) {
        for case .load(_, let url, _) in effects where loadErrors.contains(where: { $0.url == url }) {
            loadErrors.removeAll { $0.url == url }
        }
        if let ms = engine.apply(effects, for: label, receivedAt: receivedAt) {
            advanced.recordSwitch(ms: ms, go: effects.contains { if case .show = $0 { true } else { false } })
        }
        for case .notice(let notice) in effects {
            Log.deferred("notice: \(Strings(lang: .en, keyMap: keyMap).notice(notice))")
            self.notice = notice
            noticeAt = Date()
        }
        syncMode()
        saveState()
        tick()
        if effects.contains(.quit) {
            commitDrafts()
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
        if presentationPending != nil, now >= presentationPendingUntil { presentationPending = nil }
        if deletePending != nil, now >= deletePendingUntil { deletePending = nil }
        if editNotice != nil, now.timeIntervalSince(editNoticeAt) >= Self.noticeSeconds { editNotice = nil }
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

    // Probes run off the main thread and are kept per file, so an edit probes only the clips it added.
    private func checkShow() {
        showCheck?.cancel()
        // Loop logos are probed like clips.
        let loops = (document?.logos ?? []).compactMap { logo -> URL? in
            if case .loop(let url)? = logo { url } else { nil }
        }
        let urls = Set(
            state.cues.compactMap { cue -> URL? in if case .clip(_, let url) = cue.kind { url } else { nil } } + loops)
        let missing = urls.subtracting(probes.keys)
        evaluateShow(pending: missing)
        checking = !missing.isEmpty
        guard !missing.isEmpty else { return }
        showCheck = Task { [weak self] in
            await withTaskGroup(of: (URL, ClipProbe).self) { group in
                for url in missing {
                    group.addTask { (url, await PreflightRunner.probe(url)) }
                }
                for await (url, probe) in group where !Task.isCancelled {
                    self?.probed(url, probe)
                }
            }
            guard !Task.isCancelled, let self else { return }
            self.checking = false
            self.evaluateShow(pending: [])
            for finding in self.showFindings {
                let cue = finding.cueIndex.map(String.init) ?? "-"
                Log.deferred("preflight \(finding.severity) cue \(cue) \(finding.kind): \(finding.detail)")
            }
            let blocks = self.showFindings.filter { $0.severity == .block }.count
            let warnings = self.showFindings.filter { $0.severity == .warn }.count
            Log.info("preflight show: \(missing.count) files, \(blocks) blocking, \(warnings) warnings")
        }
    }

    // A clip still being probed stays out until its probe arrives, instead of showing as missing.
    private func evaluateShow(pending: Set<URL>) {
        let cues = state.cues
        let logos = document?.logos ?? []
        let findings = Preflight.evaluate(cues: cues, probes: probes, logos: logos).filter { finding in
            guard let index = finding.cueIndex, case .clip(_, let url) = cues[index].kind else { return true }
            return !pending.contains(url)
        }
        showFindings = findings + Preflight.evaluate(logos: logos, images: Set(engine.images.keys), probes: probes)
    }

    private func probed(_ url: URL, _ probe: ClipProbe) {
        probes[url] = probe
        noteDuration(url, probe.duration)
        Log.deferred(
            "probe \(url.lastPathComponent): exists \(probe.exists), playable \(probe.playable), "
                + "\(probe.width)x\(probe.height), \(probe.fps) fps, \(probe.codec), \(probe.duration) s, "
                + "video \(probe.hasVideo), audio \(probe.hasAudio)")
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
        case .confirmUnmute, .confirmMode, .confirmUnlock, .confirmQuit, .confirmQuitClick: true
        default: false
        }
    }
}
