import AppKit
import CueCore

switch CheckCommand.parse(Array(CommandLine.arguments.dropFirst())) {
case .app:
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }
case .check(let path):
    // Before any NSApplication, so no window, display, sleep assertion, state file or key map is ever touched.
    Task { exit(await Check.run(path: path)) }
    dispatchMain()
case .usage:
    try? FileHandle.standardError.write(contentsOf: Data(CheckCommand.usage(program: AppInfo.name).utf8))
    exit(CheckCommand.usageExitCode)
}
