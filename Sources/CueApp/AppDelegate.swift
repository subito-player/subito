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

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: AppModel?
    private var controlWindow: ControlWindow?
    private var keyMonitor: Any?
    private var activity: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if handOverToRunningInstance() { return }
        Log.pruneOldFiles()
        Log.info("launch \(AppInfo.name) \(AppInfo.version ?? "dev")")
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .userInitiated],
            reason: "Projector output must stay on during a show"
        )
        installMainMenu()
        let model = AppModel(showPath: CommandLine.arguments.dropFirst().first { !$0.hasPrefix("-") })
        self.model = model
        let control = ControlWindow(model: model)
        controlWindow = control
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak model] event in
            guard let model else { return event }
            return model.keyDown(event)
        }
        control.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // Dock Quit, logout and update restarts get the same press-twice confirmation as Cmd+Q.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let model, !model.quitConfirmed else { return .terminateNow }
        Log.info("quit requested by the system, treated as requestQuit")
        model.send(.requestQuit)
        return model.quitConfirmed ? .terminateNow : .terminateCancel
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

    @objc private func quitFromMenu() {
        model?.send(.requestQuit, chord: KeyChord(key: "Q", modifiers: [.command]))
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
