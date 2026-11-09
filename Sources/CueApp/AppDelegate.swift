import AppKit
import CueCore

enum AppInfo {
    static var name: String {
        let info = Bundle.main.infoDictionary
        return info?["CFBundleDisplayName"] as? String
            ?? info?["CFBundleName"] as? String
            ?? ProcessInfo.processInfo.processName
    }

    static var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

private struct LoadedShow {
    var name = "no show loaded"
    var cues: [Cue] = []
    var logos: [URL] = []
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let defaultBreakTitle = "Szünet"

    private var controlWindow: NSWindow?
    private var controlText: NSTextView?
    private var engine: PlaybackEngine?
    private var watcher: DisplayWatcher?
    private var cursorGuard: CursorGuard?
    private var keyMonitor: Any?
    private var activity: NSObjectProtocol?
    private var keyMap: KeyMap?
    private var state = ShowState()
    private var showName = ""
    private var outputLine = "Output: checking"
    private var lastKey = "-"
    private var lastNotice = "-"
    private var errors: [String] = []
    private var quitConfirmed = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOverToRunningInstance() { return }
        Log.pruneOldFiles()
        Log.info("launch \(AppInfo.name) \(AppInfo.version ?? "dev")")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Projector output must stay on during a show"
        )
        installMainMenu()
        do {
            keyMap = try KeyMap(json: Data(KeyMap.defaultJSON.utf8))
        } catch {
            report("\(error)")
        }
        let show = loadShow()
        showName = show.name

        let engine = PlaybackEngine(logos: show.logos, defaultBreakTitle: Self.defaultBreakTitle)
        engine.onEvent = { [weak self] command in
            self?.handle(command, receivedAt: ProcessInfo.processInfo.systemUptime)
        }
        engine.onLoadError = { [weak self] _, url, message in
            self?.report("Cannot play \(url.lastPathComponent): \(message)")
        }
        self.engine = engine
        let watcher = DisplayWatcher(window: engine.window) { [weak self] status in self?.outputChanged(status) }
        self.watcher = watcher
        cursorGuard = CursorGuard { [weak watcher] in watcher?.outputDisplay }

        let control = makeControlWindow(on: Self.controlScreen(excluding: watcher.outputDisplay))
        controlWindow = control
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return self.keyDown(event)
        }
        control.makeKeyAndOrderFront(nil)
        NSApp.activate()

        // init(cues:) cannot return effects, so the first arm reaches the engine this way.
        engine.apply(state.replaceCues(show.cues), for: "open", receivedAt: ProcessInfo.processInfo.systemUptime)
        refresh()
    }

    // Dock Quit, logout and update restarts get the same press-twice confirmation as Cmd+Q.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitConfirmed else { return .terminateNow }
        lastKey = "system quit request: requestQuit"
        Log.info("quit requested by the system, treated as requestQuit")
        handle(.requestQuit, receivedAt: ProcessInfo.processInfo.systemUptime)
        return quitConfirmed ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        Log.info("terminate")
        Log.flush()
    }

    // Not enabled yet: concert mode turns it on so rehearsal can still switch apps.
    func setKiosk(_ on: Bool) {
        NSApp.presentationOptions =
            on ? [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication] : []
    }

    private func keyDown(_ event: NSEvent) -> NSEvent? {
        // Held keys must not repeat GO or seeks; every key is swallowed so nothing beeps on stage.
        guard !event.isARepeat, let chord = KeyInput.chord(for: event) else { return nil }
        let name = KeyInput.name(of: chord)
        switch keyMap?.action(for: chord) {
        case .command(let command)?:
            lastKey = "\(name): \(command)"
            Log.deferred("key \(name) -> \(command)")
            handle(command, receivedAt: event.timestamp)
        case .toggleAdvanced?:
            lastKey = "\(name): advanced view (not built yet)"
            refresh()
        case nil:
            if chord.modifiers.contains(.command), NSApp.mainMenu?.performKeyEquivalent(with: event) == true {
                return nil
            }
            lastKey = "\(name): nothing"
            refresh()
        }
        return nil
    }

    @objc private func quitFromMenu() {
        lastKey = "Cmd+Q: requestQuit"
        Log.deferred("key Cmd+Q -> requestQuit")
        handle(.requestQuit, receivedAt: ProcessInfo.processInfo.systemUptime)
    }

    private func handle(_ command: Command, receivedAt: TimeInterval) {
        guard let engine else { return }
        let effects = state.handle(command, now: Date())
        engine.apply(effects, for: "\(command)", receivedAt: receivedAt)
        for case .notice(let notice) in effects {
            lastNotice = Self.describe(notice)
            Log.deferred("notice: \(lastNotice)")
        }
        refresh()
        if effects.contains(.quit) {
            quitConfirmed = true
            // Async because this can run inside applicationShouldTerminate.
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func outputChanged(_ status: OutputStatus) {
        switch status {
        case .attached(let name, let hz, let mirrored):
            outputLine = "Output: \(name), \(String(format: "%.2f", hz)) Hz" + (mirrored ? ", MIRRORED" : "")
            cursorGuard?.keepOffOutput()
        case .missing:
            outputLine = "Output: NO PROJECTOR (output hidden, playback continues)"
        }
        refresh()
    }

    private func report(_ message: String) {
        Log.info("error: \(message)")
        errors.append(message)
        refresh()
    }

    private func loadShow() -> LoadedShow {
        guard let path = CommandLine.arguments.dropFirst().first(where: { !$0.hasPrefix("-") }) else {
            return LoadedShow()
        }
        let url = URL(fileURLWithPath: path).standardizedFileURL
        do {
            var isFolder: ObjCBool = false
            if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
                let movieURL = try ShowLoader.importFolder(url)
                let movie = try ShowLoader.loadMovie(at: movieURL)
                return LoadedShow(name: movie.title, cues: ShowLoader.flatten(movie: movie, at: movieURL))
            }
            if url.lastPathComponent.hasSuffix(".concert.json") {
                let loaded = try ShowLoader.loadConcert(at: url)
                // Loop logos fail as images and so count as missing, keeping logo numbers aligned.
                let logos = loaded.concert.logos.map { logo in
                    switch logo {
                    case .image(let path), .loop(let path): ShowLoader.resolve(path, relativeTo: url)
                    }
                }
                return LoadedShow(name: loaded.concert.title, cues: ShowLoader.flatten(loaded), logos: logos)
            }
            let movie = try ShowLoader.loadMovie(at: url)
            return LoadedShow(name: movie.title, cues: ShowLoader.flatten(movie: movie, at: url))
        } catch {
            report((error as? ShowError)?.description ?? "\(url.lastPathComponent): \(error.localizedDescription)")
            return LoadedShow()
        }
    }

    private func refresh() {
        let live = state.livePlaying ? "playing" : "paused"
        let cover = state.cover.map { $0 == .black ? "black" : "logo" } ?? "none"
        var lines = [
            "\(AppInfo.name) \(AppInfo.version ?? "dev")  |  \(showName)",
            outputLine,
            "Live: \(live)  Cover: \(cover)  Sound: \(state.muted ? "muted" : "ON")",
            "",
        ]
        for (index, cue) in state.cues.enumerated() {
            var marker = "      "
            if index == state.liveIndex {
                marker = "LIVE  "
            } else if index == state.armedIndex {
                marker = state.armedReady ? "ARMED " : "arming"
            }
            lines.append("\(marker) \(cue.movieIndex == nil ? "" : "  ")\(Self.describe(cue))")
        }
        let pending = state.activePending(at: Date()).map(Self.describe)
        lines += ["", "Last key: \(lastKey)", "Notice: \(pending ?? lastNotice)"]
        lines += errors.map { "Error: \($0)" }
        controlText?.string = lines.joined(separator: "\n")
    }

    private static func describe(_ cue: Cue) -> String {
        switch cue.kind {
        case .clip(let clip, _):
            let number = clip.resolvedNumber.map { String(format: "%02ld", $0) } ?? "--"
            return "\(number) \(clip.resolvedTitle)"
        case .black:
            return "Black"
        case .breakScreen(let item):
            return "Break \(item.minutes) min" + (item.text.map { " \"\($0)\"" } ?? "")
        case .logo(let number):
            return "Logo \(number)"
        }
    }

    private static func describe(_ notice: Notice) -> String {
        switch notice {
        case .nothingArmed: "Nothing armed."
        case .armedNotReady: "Armed clip is not ready yet."
        case .soundLockedInConcert: "Sound is locked in concert mode."
        case .confirmUnmute: "Press M again within 3 s to turn sound on."
        case .confirmMode(let mode): "Press again within 3 s to switch to \(mode)."
        case .confirmQuit: "Press Cmd+Q again within 3 s to quit."
        }
    }

    private static func controlScreen(excluding output: CGDirectDisplayID?) -> NSScreen? {
        let candidates = NSScreen.screens.filter { $0.displayID != output }
        return candidates.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false } ?? candidates.first
    }

    private func installMainMenu() {
        let quit = NSMenuItem(title: "Quit \(AppInfo.name)", action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        let appMenu = NSMenu()
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        NSApp.mainMenu = mainMenu
    }

    private func makeControlWindow(on screen: NSScreen?) -> NSWindow {
        let size = NSSize(width: 900, height: 600)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = AppInfo.name
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = NSColor(white: 0.07, alpha: 1)
        window.acceptsMouseMovedEvents = true
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2))
        } else {
            window.center()
        }

        let scroll = NSTextView.scrollableTextView()
        scroll.frame = window.contentView?.bounds ?? .zero
        scroll.autoresizingMask = [.width, .height]
        scroll.drawsBackground = false
        if let text = scroll.documentView as? NSTextView {
            text.isEditable = false
            text.isSelectable = false
            text.drawsBackground = false
            text.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
            text.textColor = .white
            text.textContainerInset = NSSize(width: 16, height: 16)
            controlText = text
        }
        window.contentView?.addSubview(scroll)
        return window
    }

    private func handOverToRunningInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        guard let other = others.first(where: { $0.processIdentifier != own }) else { return false }
        print("\(AppInfo.name) is already running (pid \(other.processIdentifier)), activating it")
        other.activate()
        quitConfirmed = true
        NSApp.terminate(nil)
        return true
    }
}
