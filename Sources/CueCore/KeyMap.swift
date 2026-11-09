import Foundation

public enum Modifier: String, Sendable {
    case shift, option, command, control
}

public struct KeyChord: Hashable, Sendable {
    public static let namedKeys: Set<String> = [
        "Enter", "KeypadEnter", "Space", "Left", "Right", "Up", "Down", "Home", "End", "Escape", "Tab", "Delete",
        "KeypadPlus", "KeypadMinus", "PageUp", "PageDown", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9",
        "F10", "F11", "F12",
    ]
    private static let modifierNames: [String: Modifier] = [
        "Shift": .shift, "Opt": .option, "Cmd": .command, "Ctrl": .control,
    ]

    public var key: String
    public var modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier> = []) {
        self.key = key.count == 1 ? key.uppercased() : key
        self.modifiers = modifiers
    }

    public init?(_ text: String) {
        var parts = text.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        let key = parts.removeLast()
        guard key.count == 1 || Self.namedKeys.contains(key) else { return nil }
        var modifiers: Set<Modifier> = []
        for name in parts {
            guard let modifier = Self.modifierNames[name] else { return nil }
            modifiers.insert(modifier)
        }
        self.init(key: key, modifiers: modifiers)
    }
}

public enum KeyAction: Equatable, Sendable {
    case command(Command)
    case toggleAdvanced
}

public enum KeyMapError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unsupportedFormat(Int)
    case unknownChord(String)
    case unknownAction(chord: String, action: String)

    public var description: String {
        switch self {
        case .invalidJSON(let message):
            "keymap.json is not valid: \(message)"
        case .unsupportedFormat(let format):
            "keymap.json uses format \(format), but this version only reads format \(KeyMap.format). Update the app."
        case .unknownChord(let chord):
            "keymap.json: unknown key \"\(chord)\"."
        case .unknownAction(let chord, let action):
            "keymap.json: \"\(chord)\" has an unknown action \"\(action)\"."
        }
    }
}

public struct KeyMap: Sendable {
    public static let format = 1

    public static let defaultJSON = """
        {
          "format": 1,
          "keys": {
            "Enter": "go",
            "KeypadEnter": "go",
            "Space": "playPause",
            "B": "black",
            "L": "logo1",
            "Shift+L": "logo2",
            "Left": "seek:-5",
            "Right": "seek:5",
            "Shift+Left": "seek:-30",
            "Shift+Right": "seek:30",
            "Opt+Left": "park:-5",
            "Opt+Right": "park:5",
            "Opt+Shift+Left": "park:-30",
            "Opt+Shift+Right": "park:30",
            "Up": "armPrevious",
            "KeypadMinus": "armPrevious",
            "Down": "armNext",
            "KeypadPlus": "armNext",
            "0": "arm:0",
            "1": "arm:1",
            "2": "arm:2",
            "3": "arm:3",
            "4": "arm:4",
            "5": "arm:5",
            "6": "arm:6",
            "7": "arm:7",
            "8": "arm:8",
            "9": "arm:9",
            "Home": "restart",
            "M": "mute",
            "Cmd+Opt+D": "advanced"
          }
        }
        """

    private var actions: [KeyChord: KeyAction] = [:]

    public init(json: Data) throws {
        let keys: [String: String]
        let decoder = JSONDecoder()
        do {
            // Header first so a newer format reports "update the app" instead of a parse error.
            let format = try decoder.decode(Header.self, from: json).format
            if format > Self.format { throw KeyMapError.unsupportedFormat(format) }
            keys = try decoder.decode(Body.self, from: json).keys
        } catch let error as KeyMapError {
            throw error
        } catch {
            throw KeyMapError.invalidJSON(ShowLoader.describe(error))
        }
        for (text, name) in keys {
            guard let chord = KeyChord(text) else { throw KeyMapError.unknownChord(text) }
            guard let action = Self.action(named: name) else {
                throw KeyMapError.unknownAction(chord: text, action: name)
            }
            actions[chord] = action
        }
    }

    // A stray Shift or Option still hits the plain binding; Command and Control never fall through.
    public func action(for chord: KeyChord) -> KeyAction? {
        let strip: [Set<Modifier>] = [[], [.shift], [.option], [.shift, .option]]
        for extra in strip {
            let candidate = KeyChord(key: chord.key, modifiers: chord.modifiers.subtracting(extra))
            if let action = actions[candidate] { return action }
        }
        return nil
    }

    private struct Header: Decodable {
        var format: Int
    }

    private struct Body: Decodable {
        var keys: [String: String]
    }

    private static func action(named name: String) -> KeyAction? {
        switch name {
        case "go": return .command(.go)
        case "playPause": return .command(.playPause)
        case "black": return .command(.toggleCover(.black))
        case "logo1": return .command(.toggleCover(.logo(1)))
        case "logo2": return .command(.toggleCover(.logo(2)))
        case "restart": return .command(.restartLive)
        case "armNext": return .command(.armNext)
        case "armPrevious": return .command(.armPrevious)
        case "mute": return .command(.toggleMute)
        case "advanced": return .toggleAdvanced
        default: break
        }
        let parts = name.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        if parts[0] == "arm", let number = Int(parts[1]) { return .command(.armNumber(number)) }
        guard let seconds = Double(parts[1]), seconds.isFinite else { return nil }
        switch parts[0] {
        case "seek": return .command(.seekLive(by: seconds))
        case "park": return .command(.parkArmed(by: seconds))
        default: return nil
        }
    }
}
