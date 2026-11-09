import AppKit

final class OutputWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controlWindow: NSWindow?
    private var outputWindow: OutputWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        controlWindow = makeControlWindow(on: Self.controlScreen())
        if let screen = Self.outputScreen() {
            outputWindow = makeOutputWindow(on: screen)
        } else {
            print("no output display")
        }
        controlWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        // Stopgap until task 4's DisplayWatcher replaces it.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged() {
        guard let window = outputWindow else { return }
        if let screen = Self.outputScreen() {
            window.setFrame(screen.frame, display: false)
            window.orderFrontRegardless()
        } else {
            window.orderOut(nil)
        }
    }

    // The laptop panel hosts control; the output must never land on it.
    private static func controlScreen() -> NSScreen? {
        NSScreen.screens.first(where: isBuiltIn) ?? NSScreen.screens.first
    }

    private static func outputScreen() -> NSScreen? {
        let control = controlScreen()
        return NSScreen.screens.first { $0 != control }
    }

    private static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return false
        }
        return CGDisplayIsBuiltin(id.uint32Value) != 0
    }

    private func installMainMenu() {
        let quit = NSMenuItem(
            title: "Quit \(AppInfo.name)",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
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
        if let frame = screen?.visibleFrame {
            window.setFrameOrigin(
                NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
            )
        } else {
            window.center()
        }

        let text = AppInfo.version.map { "\(AppInfo.name) v\($0)" } ?? AppInfo.name
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 48, weight: .semibold)
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        if let content = window.contentView {
            content.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: content.centerYAnchor),
            ])
        }
        return window
    }

    private func makeOutputWindow(on screen: NSScreen) -> OutputWindow {
        let window = OutputWindow(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.setFrame(screen.frame, display: false)
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
        window.orderFrontRegardless()
        return window
    }
}
