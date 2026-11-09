import AppKit
import CoreGraphics

enum OutputStatus: Equatable {
    case attached(name: String?, hz: Double, mirrored: Bool)
    case missing
}

struct DisplayChoice: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String?
    let saved: Bool
}

@MainActor
final class DisplayWatcher {
    private static let savedKey = "outputDisplay"

    var onChange: (OutputStatus) -> Void = { _ in }
    private(set) var outputDisplay: CGDirectDisplayID?
    private let window: NSWindow
    private var reattachScheduled = false
    private var configuring = false
    private var status: OutputStatus?
    private var observer: NSObjectProtocol?

    init(window: NSWindow, onChange: @escaping (OutputStatus) -> Void) {
        self.window = window
        self.onChange = onChange
        CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReattach() }
        }
        reattach()
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    static var hasSavedChoice: Bool {
        savedIdentity != nil
    }

    static func choices() -> [DisplayChoice] {
        let saved = savedIdentity
        return externalDisplays().map { DisplayChoice(id: $0, name: name(of: $0), saved: identity(of: $0) == saved) }
    }

    // Called by the control screen's display picker; nil goes back to the first external display.
    func setPreferred(_ display: CGDirectDisplayID?) {
        if let display {
            UserDefaults.standard.set(Self.identity(of: display), forKey: Self.savedKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.savedKey)
        }
        reattach()
    }

    fileprivate func reconfiguring(_ display: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        if flags.contains(.beginConfigurationFlag) {
            // Before macOS moves windows off a vanishing display, so the output never lands on the laptop.
            configuring = true
            window.orderOut(nil)
            Log.info("display \(display) reconfiguring, output hidden")
        } else {
            configuring = false
            scheduleReattach()
        }
    }

    private func scheduleReattach() {
        guard !reattachScheduled else { return }
        reattachScheduled = true
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                self?.reattachScheduled = false
                self?.reattach()
            }
        }
    }

    private func reattach() {
        guard !configuring else { return }
        guard let display = pickOutput() else {
            outputDisplay = nil
            window.orderOut(nil)
            let mirror = Self.laptopMirror()
            let hz = mirror.flatMap { CGDisplayCopyDisplayMode($0)?.refreshRate } ?? 0
            report(mirror == nil ? .missing : .attached(name: nil, hz: hz, mirrored: true))
            return
        }
        outputDisplay = display
        window.setFrame(Self.appKitFrame(of: display), display: true)
        window.orderFrontRegardless()
        let hz = CGDisplayCopyDisplayMode(display)?.refreshRate ?? 0
        report(.attached(name: Self.name(of: display), hz: hz, mirrored: CGDisplayIsInMirrorSet(display) != 0))
    }

    private func report(_ new: OutputStatus) {
        if new != status { Log.info("output \(new)") }
        status = new
        onChange(new)
    }

    // Quartz is top-left based on the main display, AppKit bottom-left; NSScreen can still be stale here.
    private static func appKitFrame(of display: CGDirectDisplayID) -> NSRect {
        let bounds = CGDisplayBounds(display)
        let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
        return NSRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
    }

    private func pickOutput() -> CGDirectDisplayID? {
        let externals = Self.externalDisplays()
        let saved = Self.savedIdentity
        return externals.first { Self.identity(of: $0) == saved } ?? externals.first
    }

    private static var savedIdentity: [Int]? {
        UserDefaults.standard.array(forKey: savedKey) as? [Int]
    }

    // A mirror of the laptop panel already shows the control screen, so it is never an output.
    private static func laptopMirror() -> CGDirectDisplayID? {
        let online = displays(CGGetOnlineDisplayList)
        guard let builtIn = online.first(where: { CGDisplayIsBuiltin($0) != 0 }) else { return nil }
        return online.first {
            CGDisplayIsBuiltin($0) == 0 && CGDisplayPrimaryDisplay($0) == CGDisplayPrimaryDisplay(builtIn)
        }
    }

    // Built-in from the online list: under hardware mirroring only one of the pair is active.
    private static func externalDisplays() -> [CGDirectDisplayID] {
        let displays = activeDisplays()
        let builtIn = Self.displays(CGGetOnlineDisplayList).first { CGDisplayIsBuiltin($0) != 0 }
        return displays.filter { display in
            guard CGDisplayIsBuiltin(display) == 0 else { return false }
            guard let builtIn else { return true }
            return CGDisplayPrimaryDisplay(display) != CGDisplayPrimaryDisplay(builtIn)
        }
    }

    private static func name(of display: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { $0.displayID == display }?.localizedName
    }

    private static func identity(of display: CGDirectDisplayID) -> [Int] {
        [CGDisplayVendorNumber(display), CGDisplayModelNumber(display), CGDisplaySerialNumber(display)].map(Int.init)
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        displays(CGGetActiveDisplayList)
    }

    private static func displays(
        _ list: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError
    ) -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard list(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard list(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}

private func displayReconfigured(
    _ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags, _ info: UnsafeMutableRawPointer?
) {
    guard let info else { return }
    let watcher = Unmanaged<DisplayWatcher>.fromOpaque(info).takeUnretainedValue()
    if Thread.isMainThread {
        MainActor.assumeIsolated { watcher.reconfiguring(display, flags: flags) }
    } else {
        DispatchQueue.main.async { MainActor.assumeIsolated { watcher.reconfiguring(display, flags: flags) } }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
