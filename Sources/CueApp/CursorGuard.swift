import AppKit
import CoreGraphics
import CueCore

@MainActor
final class CursorGuard {
    private let outputDisplay: () -> CGDirectDisplayID?
    private var monitors: [Any] = []

    init(outputDisplay: @escaping () -> CGDirectDisplayID?) {
        self.outputDisplay = outputDisplay
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in self?.keepOffOutput() }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.keepOffOutput()
            return event
        }
        monitors = [global, local].compactMap { $0 }
        keepOffOutput()
    }

    // Quartz coordinates throughout (CGEvent, CGDisplayBounds, CGWarp), so no AppKit y-flip is involved.
    func keepOffOutput() {
        guard let output = outputDisplay(), let cursor = CGEvent(source: nil)?.location else { return }
        let outputBounds = CGDisplayBounds(output)
        guard outputBounds.contains(cursor) else { return }
        let control = DisplayWatcher.activeDisplays()
            .filter { CGDisplayPrimaryDisplay($0) != CGDisplayPrimaryDisplay(output) }
            .map(CGDisplayBounds)
        guard let target = ScreenGeometry.nearestPoint(to: cursor, inAnyOf: control) else { return }
        CGWarpMouseCursorPosition(target)
        CGAssociateMouseAndMouseCursorPosition(1)
    }
}
