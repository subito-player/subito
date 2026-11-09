import AppKit
import CueCore

enum KeyInput {
    private static let namedKeyCodes: [UInt16: String] = [
        36: "Enter", 76: "KeypadEnter", 49: "Space", 123: "Left", 124: "Right", 125: "Down", 126: "Up",
        115: "Home", 119: "End", 116: "PageUp", 121: "PageDown", 53: "Escape", 48: "Tab", 51: "Delete",
        69: "KeypadPlus", 78: "KeypadMinus",
        82: "0", 83: "1", 84: "2", 85: "3", 86: "4", 87: "5", 88: "6", 89: "7", 91: "8", 92: "9",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
    ]

    static func chord(for event: NSEvent) -> KeyChord? {
        let key: String
        if let named = namedKeyCodes[event.keyCode] {
            key = named
        } else if let characters = event.characters(byApplyingModifiers: []), characters.count == 1 {
            // No modifiers applied, so Shift+1 still reads "1" on any layout and Shift+L reads "l".
            key = characters.uppercased()
        } else {
            return nil
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Set<Modifier> = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.control) { modifiers.insert(.control) }
        return KeyChord(key: key, modifiers: modifiers)
    }

    static func name(of chord: KeyChord) -> String {
        let order: [(Modifier, String)] = [(.control, "Ctrl"), (.command, "Cmd"), (.option, "Opt"), (.shift, "Shift")]
        let prefix = order.filter { chord.modifiers.contains($0.0) }.map { $0.1 + "+" }.joined()
        return prefix + chord.key
    }
}
