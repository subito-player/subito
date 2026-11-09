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

    // Control: the built-in panel when online (lid open), else the main display. The output is never the
    // control screen or its mirror; a picked display wins while it is present.
    public init(displays: [DisplayInfo], main: UInt32, preferred: UInt32?) {
        let control = displays.first(where: \.builtIn)?.id ?? main
        let group = displays.first { $0.id == control }?.mirrorOf ?? control
        let candidates = displays.filter { $0.active && $0.id != control && $0.mirrorOf != group }.map(\.id)
        self.control = control
        self.candidates = candidates
        output = preferred.flatMap { candidates.contains($0) ? $0 : nil } ?? candidates.first
        mirror = displays.first { $0.id != control && $0.mirrorOf == group }?.id
    }
}
