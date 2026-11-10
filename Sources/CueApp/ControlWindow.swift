import AppKit
import CueCore
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
        let pickers = Pickers(
            openShow: { [weak self] in self?.chooseShow() },
            newMovie: { [weak self] in self?.newMovie() },
            newConcert: { [weak self] in self?.newConcert() },
            addClips: { [weak self] in self?.addClips() },
            addMovie: { [weak self] in self?.addMovie() },
            pictureFile: { [weak self] number in self?.choosePicture(number) })
        let host = NSHostingView(
            rootView: ControlView(model: model, focusControl: { [weak self] in self?.takeFocus() }, pickers: pickers))
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
        let control = DisplayWatcher.roles().control
        let screens = NSScreen.screens
        guard
            let screen = screens.first(where: { $0.displayID == control })
                ?? screens.first(where: { $0.displayID != model.outputDisplay })
        else { return }
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

    // The field editor of a focused text field; the key monitor then passes keys to it.
    var isTyping: Bool {
        firstResponder is NSText
    }

    func endTyping() {
        if isTyping { _ = makeFirstResponder(nil) }
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let made = super.makeFirstResponder(responder)
        syncTyping()
        return made
    }

    // A click anywhere but the field being edited ends the typing, as Enter does.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, let editor = firstResponder as? NSTextView,
            let hit = contentView?.hitTest(event.locationInWindow),
            !(hit === editor || (editor.delegate as? NSView).map(hit.isDescendant(of:)) == true)
        {
            endTyping()
        }
        super.sendEvent(event)
        syncTyping()
    }

    private func syncTyping() {
        if model.typing != isTyping { model.typing = isTyping }
    }

    private func chooseShow() {
        let s = model.strings
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.json]
        panel.message = s.openMessage
        panel.prompt = s.open
        present(panel, rehearsalOnly: true) { [weak self] urls in
            if let url = urls.first { self?.model.open(url.path) }
        }
    }

    // A new or empty folder becomes an empty movie, so one picker covers both ways to start a movie.
    private func newMovie() {
        let s = model.strings
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.message = s.newMovieMessage
        panel.prompt = s.create
        present(panel, rehearsalOnly: true) { [weak self] urls in
            if let url = urls.first { self?.model.open(url.path) }
        }
    }

    private func newConcert() {
        let s = model.strings
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = s.newConcertName + ".concert.json"
        panel.message = s.newConcertMessage
        panel.prompt = s.create
        present(panel, rehearsalOnly: true) { [weak self] urls in
            if let url = urls.first { self?.model.createConcert(at: url) }
        }
    }

    private func addClips() {
        let s = model.strings
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie]
        panel.message = s.addClipsMessage
        panel.prompt = s.add
        present(panel) { [weak self] urls in self?.model.addClips(urls) }
    }

    private func addMovie() {
        let s = model.strings
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowedContentTypes = [.json]
        panel.message = s.addMovieMessage
        panel.prompt = s.add
        present(panel) { [weak self] urls in
            if let url = urls.first { self?.model.addMovie(url) }
        }
    }

    // Starts in the show folder, where a concert pick is stored as a relative path; only these videos loop.
    private func choosePicture(_ number: Int) {
        let s = model.strings
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.allowedContentTypes =
            [.image] + ShowLoader.playableExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        panel.directoryURL = model.document?.url.deletingLastPathComponent()
        panel.message = s.pictureFileMessage(number)
        panel.prompt = s.choose
        present(panel) { [weak self] urls in
            if let url = urls.first { self?.model.setPictureFile(number, url) }
        }
    }

    // A sheet stays on the control screen, never under the output window; a locked concert opens none.
    private func present(_ panel: NSSavePanel, rehearsalOnly: Bool = false, then done: @escaping ([URL]) -> Void) {
        let allowed = rehearsalOnly ? model.state.mode == .rehearsal : model.canEdit
        guard attachedSheet == nil, allowed else { return }
        endTyping()
        model.filePickerOpen = true
        panel.beginSheetModal(for: self) { [weak self] response in
            self?.model.filePickerOpen = false
            guard response == .OK else { return }
            done((panel as? NSOpenPanel)?.urls ?? panel.url.map { [$0] } ?? [])
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
