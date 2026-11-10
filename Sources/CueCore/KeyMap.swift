import Foundation

public enum Modifier: String, Sendable {
    case shift, option, command, control
}

public struct KeyChord: Hashable, Sendable {
    public static let namedKeys: Set<String> = [
        "Enter", "KeypadEnter", "Space", "Left", "Right", "Up", "Down", "Home", "End", "Escape", "Tab", "Delete",
        "KeypadPlus", "KeypadMinus", "PageUp", "PageDown", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9",
        "F10", "F11", "F12", "Num0", "Num1", "Num2", "Num3", "Num4", "Num5", "Num6", "Num7", "Num8", "Num9",
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

    // Ctrl, Cmd, Opt, Shift: one spelling per chord, and keymap.json reads it back.
    public var name: String {
        let order: [(Modifier, String)] = [(.control, "Ctrl"), (.command, "Cmd"), (.option, "Opt"), (.shift, "Shift")]
        return order.filter { modifiers.contains($0.0) }.map { $0.1 + "+" }.joined() + key
    }

    // For people: arrows as symbols and key names in the operator's language.
    public func label(_ lang: Lang) -> String {
        let shared = [
            "Left": "←", "Right": "→", "Up": "↑", "Down": "↓", "Escape": "Esc", "PageUp": "Page Up",
            "PageDown": "Page Down",
        ]
        let names =
            lang == .hu
            ? [
                "Space": "Szóköz", "KeypadEnter": "Num Enter", "KeypadPlus": "Num +", "KeypadMinus": "Num -",
                "Delete": "Törlés",
            ]
            : ["KeypadEnter": "Keypad Enter", "KeypadPlus": "Keypad +", "KeypadMinus": "Keypad -"]
        let digit = key.hasPrefix("Num") ? (lang == .hu ? "Num " : "Keypad ") + key.dropFirst(3) : nil
        return KeyChord(key: names[key] ?? shared[key] ?? digit ?? key, modifiers: modifiers).name
    }

    // Plain keys before keypad ones, then fewer modifiers, so the main key leads wherever one is shown.
    fileprivate var order: (Int, Int, String, String) {
        let keypad = key.hasPrefix("Keypad") || key.hasPrefix("Num")
        return (keypad ? 1 : 0, modifiers.count, modifiers.map(\.rawValue).sorted().joined(), key)
    }
}

public enum KeyAction: Equatable, Sendable {
    case command(Command)
    case toggleAdvanced
}

public enum KeyMapError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case unreadable(String)
    case unsupportedFormat(Int)
    case unknownChord(String)
    case unknownAction(chord: String, action: String)
    // The app reads keys unshifted, so "?" would never match; "use" is the chord that does.
    case shiftedKey(chord: String, use: String)
    case noGo

    public var description: String {
        switch self {
        case .invalidJSON(let message):
            "keymap.json is not valid: \(message)"
        case .unreadable(let message):
            "keymap.json cannot be read: \(message)"
        case .unsupportedFormat(let format):
            "keymap.json uses format \(format), but this version only reads format \(KeyMap.format). Update the app."
        case .unknownChord(let chord):
            "keymap.json: unknown key \"\(chord)\"."
        case .unknownAction(let chord, let action):
            "keymap.json: \"\(chord)\" has an unknown action \"\(action)\"."
        case .shiftedKey(let chord, let use):
            "keymap.json: \"\(chord)\" needs Shift on a US keyboard; write \"\(use)\" instead."
        case .noGo:
            "keymap.json has no key for GO."
        }
    }
}

public struct KeyMap: Equatable, Sendable {
    public static let format = 1
    // US layout: the character Shift makes, and the key it is on.
    static let shiftedKeys: [String: String] = [
        "~": "`", "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8", "(": "9",
        ")": "0", "_": "-", "{": "[", "}": "]", "|": "\\", ":": ";", "\"": "'", "<": ",", ">": ".", "?": "/",
    ]

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
            "Num1": "slot:1",
            "Num2": "slot:2",
            "Num3": "slot:3",
            "Num4": "slot:4",
            "Num5": "slot:5",
            "Num6": "slot:6",
            "Home": "restart",
            "M": "mute",
            "Ctrl+Opt+D": "advanced"
          }
        }
        """

    // The v0.2 default, without slots; a keymap.json still holding it gets the current default.
    static let v02DefaultJSON = """
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
            "Ctrl+Opt+D": "advanced"
          }
        }
        """

    // defaultJSON and v02DefaultJSON are pinned by the tests, so parsing them cannot fail.
    public static let standard = try! KeyMap(json: Data(defaultJSON.utf8))
    private static let v02Default = try! KeyMap(json: Data(v02DefaultJSON.utf8))

    private var bindings: [KeyChord: KeyAction] = [:]

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
            if let base = Self.shiftedKeys[chord.key] {
                let use = KeyChord(key: base, modifiers: chord.modifiers.union([.shift]))
                throw KeyMapError.shiftedKey(chord: text, use: use.name)
            }
            guard let action = Self.action(named: name) else {
                throw KeyMapError.unknownAction(chord: text, action: name)
            }
            bindings[chord] = action
        }
    }

    // A missing file, or one with the v0.2 default keys, gets the current default; any other file is the owner's.
    @discardableResult
    public static func installDefault(at url: URL) throws -> Bool {
        if FileManager.default.fileExists(atPath: url.path) {
            guard let data = try? Data(contentsOf: url), (try? KeyMap(json: data)) == v02Default else { return false }
        } else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        try Data((defaultJSON + "\n").utf8).write(to: url, options: .atomic)
        return true
    }

    // A broken file, or one without GO, falls back to the default map, so the show keys always work.
    public static func load(from url: URL) -> (map: KeyMap, error: KeyMapError?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (standard, nil) }
        do {
            let map = try KeyMap(json: try Data(contentsOf: url))
            return map.chords(for: .command(.go)).isEmpty ? (standard, .noGo) : (map, nil)
        } catch let error as KeyMapError {
            return (standard, error)
        } catch {
            return (standard, .unreadable(error.localizedDescription))
        }
    }

    // Every bound action once, in no particular order.
    public var actions: [KeyAction] {
        bindings.values.reduce(into: []) { list, action in
            if !list.contains(action) { list.append(action) }
        }
    }

    public func chords(for action: KeyAction) -> [KeyChord] {
        bindings.filter { $0.value == action }.map(\.key).sorted { $0.order < $1.order }
    }

    // Slots no key reaches; a customised keymap.json is never rewritten, so the app says so instead.
    public var slotsWithoutKeys: [Int] {
        (1...slotCount).filter { chords(for: .command(.toggleCover(.logo($0 + logoCount)))).isEmpty }
    }

    // Stray Shift/Option falls to the plain binding, never an arm-by-number one (Opt+Shift+4 is a screenshot).
    public func action(for chord: KeyChord) -> KeyAction? {
        let strip: [Set<Modifier>] = [[], [.shift], [.option], [.shift, .option]]
        for extra in strip {
            let candidate = KeyChord(key: chord.key, modifiers: chord.modifiers.subtracting(extra))
            guard let action = bindings[candidate] else { continue }
            if case .command(.armNumber) = action, !extra.isEmpty { continue }
            return action
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
        if parts[0] == "slot" {
            guard let number = Int(parts[1]), (1...slotCount).contains(number) else { return nil }
            return .command(.toggleCover(.logo(number + logoCount)))
        }
        guard let seconds = Double(parts[1]), seconds.isFinite else { return nil }
        switch parts[0] {
        case "seek": return .command(.seekLive(by: seconds))
        case "park": return .command(.parkArmed(by: seconds))
        default: return nil
        }
    }
}
