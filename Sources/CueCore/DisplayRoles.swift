import Foundation

// Ids are CGDirectDisplayID values; CueCore stays Foundation only.
public struct DisplayInfo: Equatable, Sendable {
    public var id: UInt32
    // The mirror set's primary display, or the display itself when it is not mirrored.
    public var mirrorOf: UInt32
    public var builtIn: Bool
    public var active: Bool

    public init(id: UInt32, mirrorOf: UInt32? = nil, builtIn: Bool = false, active: Bool = true) {
        self.id = id
        self.mirrorOf = mirrorOf ?? id
        self.builtIn = builtIn
        self.active = active
    }
}

public struct DisplayRoles: Equatable, Sendable {
    public var control: UInt32
    // Displays that may be the output, in macOS order.
    public var candidates: [UInt32]
    public var output: UInt32?
    // Shows the control screen, so it is never an output.
    public var mirror: UInt32?

    // Control: lid-open panel, else main unless main is the active saved pick; output never shows control.
    public init(displays: [DisplayInfo], main: UInt32, preferred: UInt32?) {
        let groupOf = { (id: UInt32) in displays.first { $0.id == id }?.mirrorOf ?? id }
        let builtIn = displays.first(where: \.builtIn)?.id
        var control = builtIn ?? main
        if builtIn == nil, let preferred, displays.contains(where: { $0.id == preferred && $0.active }),
            groupOf(preferred) == groupOf(main),
            let other = displays.first(where: { $0.active && $0.mirrorOf != groupOf(main) })
        {
            control = other.id
        }
        let group = groupOf(control)
        let candidates = displays.filter { $0.active && $0.id != control && $0.mirrorOf != group }.map(\.id)
        self.control = control
        self.candidates = candidates
        output = preferred.flatMap { candidates.contains($0) ? $0 : nil } ?? candidates.first
        mirror = displays.first { $0.id != control && $0.mirrorOf == group }?.id
    }
}
