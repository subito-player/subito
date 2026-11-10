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

    static var updateRepository: String? {
        Bundle.main.infoDictionary?["UpdateRepository"] as? String
    }

    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Bundle.main.bundleIdentifier ?? name, isDirectory: true)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controlWindow: ControlWindow?
    private var keyMonitor: Any?
    private var activity: NSObjectProtocol?

    // Settings live under the bundle ID, so the first launch after a rename starts from the old name's copy.
    private func copySettingsFromPreviousName() {
        let info = Bundle.main.infoDictionary
        guard let old = info?["PreviousBundleIdentifier"] as? String, !old.isEmpty, old != Bundle.main.bundleIdentifier
        else { return }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        do {
            let source = base.appendingPathComponent(old, isDirectory: true)
            if try Rename.copySupportFolder(from: source, to: AppInfo.supportDirectory) {
                Log.info("settings copied from \(source.path)")
            }
        } catch {
            Log.info("error: cannot copy settings from \(old): \(error.localizedDescription)")
        }
        guard let previous = UserDefaults(suiteName: old) else { return }
        for key in [Lang.savedKey, DisplayWatcher.savedKey] where UserDefaults.standard.object(forKey: key) == nil {
            if let value = previous.object(forKey: key) { UserDefaults.standard.set(value, forKey: key) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOverToRunningInstance() { return }
        Log.pruneOldFiles()
        Log.info("launch \(AppInfo.name) \(AppInfo.version ?? "dev")")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Projector output must stay on during a show"
        )
        installMainMenu()
        copySettingsFromPreviousName()
        let argument = LaunchArguments.showPath(Array(CommandLine.arguments.dropFirst()))
        // Read before the model writes cleanExit = false over it.
        let saved = StateFile.load()
        let plan = Recovery.plan(from: saved, launchArgument: argument.map(StateFile.showPath))
        Log.info("launch plan \(plan)")
        // The mode outlives a clean quit too; only a crash recovery also brings back the live cue.
        let model = AppModel(
            plan: plan, recoveries: Recovery.recoveries(for: plan, from: saved), mode: saved?.mode ?? .rehearsal)
        self.model = model
        let control = ControlWindow(model: model)
        controlWindow = control
        // File pickers and text fields get their own keys, so their Enter can never fire GO.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model, weak control] event in
            guard let model, let control, event.window === control, control.attachedSheet == nil else { return event }
            guard control.isTyping else { return model.keyDown(event) }
            switch event.keyCode {
            case 53:
                model.cancelTyping()
                control.endTyping()
                return nil
            case 36, 76:
                // After the field has taken its Enter, so the next key drives the show again.
                DispatchQueue.main.async { control.endTyping() }
                return event
            default:
                return event
            }
        }
        control.makeKeyAndOrderFront(nil)
        NSApp.activate()
        model.onModeChange = { [weak self] mode in self?.setKiosk(mode == .concert) }
        model.onLanguageChange = { [weak self] in self?.installMainMenu() }
        setKiosk(model.state.mode == .concert)
    }

    // Dock Quit, logout and update restarts get the same press-twice confirmation as Cmd+Q.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.quitConfirmed else { return .terminateNow }
        Log.info("quit requested by the system, treated as requestQuit")
        model.send(.requestQuit)
        return model.quitConfirmed ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.converter.shutDown()
        model?.commitDrafts()
        if let model, model.quitConfirmed { model.saveState(cleanExit: true) }
        Log.info("terminate")
        Log.flush()
    }

    // Concert only, so rehearsal can still switch apps.
    func setKiosk(_ on: Bool) {
        NSApp.presentationOptions =
            on ? [.hideDock, .hideMenuBar, .disableProcessSwitching, .disableHideApplication] : []
        // The visible frame grows or shrinks with the Dock and menu bar, so the window refills it.
        controlWindow?.place()
    }

    @objc private func quitFromMenu() {
        model?.send(.requestQuit, chord: KeyChord(key: "Q", modifiers: [.command]))
    }

    private func installMainMenu() {
        let s = model?.strings ?? Strings(lang: .saved)
        let quit = NSMenuItem(title: s.quit(AppInfo.name), action: #selector(quitFromMenu), keyEquivalent: "q")
        quit.target = self
        let appMenu = NSMenu()
        appMenu.addItem(quit)
        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        // Copy, paste and select all in the editor's text fields; they act only while one is focused.
        let editMenu = NSMenu(title: s.edit)
        editMenu.addItem(withTitle: s.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: s.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: s.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: s.selectAll, action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem()
        editItem.submenu = editMenu
        let mainMenu = NSMenu()
        mainMenu.addItem(appItem)
        mainMenu.addItem(editItem)
        NSApp.mainMenu = mainMenu
    }

    // No model yet, so applicationShouldTerminate lets this quit through unconfirmed.
    private func handOverToRunningInstance() -> Bool {
        guard let id = Bundle.main.bundleIdentifier else { return false }
        let own = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
        guard let other = others.first(where: { $0.processIdentifier != own }) else { return false }
        print("\(AppInfo.name) is already running (pid \(other.processIdentifier)), activating it")
        other.activate()
        NSApp.terminate(nil)
        return true
    }
}
