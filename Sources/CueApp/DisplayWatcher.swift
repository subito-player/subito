import AppKit
import CoreGraphics
import CueCore

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
    static let savedKey = "outputDisplay"

    var onChange: (OutputStatus) -> Void = { _ in }
    // False while rehearsal shows the output in a window or not at all: the watcher then only reports.
    var placesWindow = true {
        didSet {
            guard placesWindow, !oldValue else { return }
            // Mid-reconfiguration the end of it re-attaches; until then the output stays hidden, as at its start.
            if configuring { window.orderOut(nil) }
            reattach()
        }
    }
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
        return roles().candidates.map { DisplayChoice(id: $0, name: name(of: $0), saved: identity(of: $0) == saved) }
    }

    // One source for the control screen, the output, the picker and the cursor guard.
    static func roles() -> DisplayRoles {
        let online = displays(CGGetOnlineDisplayList)
        let active = Set(displays(CGGetActiveDisplayList))
        let infos = online.map { display in
            DisplayInfo(
                id: display, mirrorOf: CGDisplayPrimaryDisplay(display), builtIn: CGDisplayIsBuiltin(display) != 0,
                active: active.contains(display))
        }
        let saved = savedIdentity
        let preferred = saved.flatMap { saved in online.first { identity(of: $0) == saved } }
        return DisplayRoles(displays: infos, main: CGMainDisplayID(), preferred: preferred)
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
            guard placesWindow else { return }
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
        let roles = Self.roles()
        guard let display = roles.output else {
            outputDisplay = nil
            if placesWindow { window.orderOut(nil) }
            let mirror = roles.mirror
            let hz = mirror.flatMap { CGDisplayCopyDisplayMode($0)?.refreshRate } ?? 0
            report(mirror == nil ? .missing : .attached(name: nil, hz: hz, mirrored: true))
            return
        }
        outputDisplay = display
        if placesWindow {
            window.setFrame(Self.appKitFrame(of: display), display: true)
            window.orderFrontRegardless()
        }
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

    private static var savedIdentity: [Int]? {
        UserDefaults.standard.array(forKey: savedKey) as? [Int]
    }

    private static func name(of display: CGDirectDisplayID) -> String? {
        NSScreen.screens.first { $0.displayID == display }?.localizedName
    }

    private static func identity(of display: CGDirectDisplayID) -> [Int] {
        [CGDisplayVendorNumber(display), CGDisplayModelNumber(display), CGDisplaySerialNumber(display)].map(Int.init)
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
