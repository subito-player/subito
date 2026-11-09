import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ControlWindow: NSWindow {
    private let model: AppModel
    private var observers: [NSObjectProtocol] = []

    init(model: AppModel) {
        self.model = model
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled], backing: .buffered,
            defer: false)
        title = AppInfo.name
        appearance = NSAppearance(named: .darkAqua)
        backgroundColor = NSColor(Palette.bg)
        isReleasedWhenClosed = false
        // It fills its screen, so a drag could only push part of it out of reach.
        isMovable = false
        for kind: NSWindow.ButtonType in [.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(kind)?.isHidden = true
        }
        let host = NSHostingView(
            rootView: ControlView(
                model: model, focusControl: { [weak self] in self?.takeFocus() },
                openShow: { [weak self] in self?.chooseShow() }))
        // The window size comes from the screen, never from the SwiftUI content.
        host.sizingOptions = []
        contentView = host

        model.onOutputChange = { [weak self] in self?.place() }
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateFocus() }
                })
        }
        place()
        updateFocus()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    func place() {
        let candidates = NSScreen.screens.filter { $0.displayID != model.outputDisplay }
        let builtIn = candidates.first { $0.displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false }
        guard let screen = builtIn ?? candidates.first else { return }
        setFrame(screen.visibleFrame, display: true)
    }

    override func becomeKey() {
        super.becomeKey()
        updateFocus()
    }

    override func resignKey() {
        super.resignKey()
        updateFocus()
    }

    // A sheet stays on the control screen, never under the output window.
    private func chooseShow() {
        guard attachedSheet == nil else { return }
        let s = model.strings
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.message = s.openMessage
        panel.prompt = s.open
        model.filePickerOpen = true
        panel.beginSheetModal(for: self) { [weak self] response in
            self?.model.filePickerOpen = false
            guard response == .OK, let url = panel.url else { return }
            self?.model.open(url.path)
        }
        updateFocus()
    }

    private func takeFocus() {
        NSApp.activate()
        makeKeyAndOrderFront(nil)
    }

    private func updateFocus() {
        let lost = !(NSApp.isActive && (isKeyWindow || attachedSheet != nil))
        if model.focusLost != lost { model.focusLost = lost }
    }
}
