import Foundation
import Testing

@testable import CueCore

@Suite struct KeyChordTests {
    @Test func modifiersParseInAnyOrder() {
        #expect(KeyChord("Opt+Shift+Right") == KeyChord(key: "Right", modifiers: [.option, .shift]))
        #expect(KeyChord("Shift+Opt+Right") == KeyChord("Opt+Shift+Right"))
        #expect(KeyChord("Cmd+Opt+D") == KeyChord(key: "D", modifiers: [.command, .option]))
        #expect(KeyChord("Ctrl+Enter") == KeyChord(key: "Enter", modifiers: [.control]))
    }

    @Test func lettersNormaliseToUppercase() {
        #expect(KeyChord("b") == KeyChord("B"))
        #expect(KeyChord(key: "b") == KeyChord("B"))
    }

    @Test func clickerAndFootswitchKeysParse() {
        #expect(KeyChord("PageDown") == KeyChord(key: "PageDown"))
        #expect(KeyChord("Shift+F12") == KeyChord(key: "F12", modifiers: [.shift]))
    }

    @Test(arguments: ["", "Shift+", "Hyper+L", "Entr", "shift+L", "+"])
    func malformedChordIsRejected(text: String) {
        #expect(KeyChord(text) == nil)
    }
}

@Suite struct KeyMapTests {
    let map: KeyMap

    init() throws {
        map = try KeyMap(json: Data(KeyMap.defaultJSON.utf8))
    }

    func action(_ text: String) throws -> KeyAction? {
        map.action(for: try #require(KeyChord(text)))
    }

    @Test func defaultMapMatchesTheDesignKeyTable() throws {
        let table: [(String, KeyAction)] = [
            ("Enter", .command(.go)),
            ("KeypadEnter", .command(.go)),
            ("Space", .command(.playPause)),
            ("B", .command(.toggleCover(.black))),
            ("L", .command(.toggleCover(.logo(1)))),
            ("Shift+L", .command(.toggleCover(.logo(2)))),
            ("Left", .command(.seekLive(by: -5))),
            ("Right", .command(.seekLive(by: 5))),
            ("Shift+Left", .command(.seekLive(by: -30))),
            ("Shift+Right", .command(.seekLive(by: 30))),
            ("Opt+Left", .command(.parkArmed(by: -5))),
            ("Opt+Right", .command(.parkArmed(by: 5))),
            ("Opt+Shift+Left", .command(.parkArmed(by: -30))),
            ("Opt+Shift+Right", .command(.parkArmed(by: 30))),
            ("Up", .command(.armPrevious)),
            ("KeypadMinus", .command(.armPrevious)),
            ("Down", .command(.armNext)),
            ("KeypadPlus", .command(.armNext)),
            ("Home", .command(.restartLive)),
            ("M", .command(.toggleMute)),
            ("Cmd+Opt+D", .toggleAdvanced),
        ]
        for (text, expected) in table {
            #expect(try action(text) == expected, "\(text)")
        }
        for digit in 0...9 {
            #expect(try action("\(digit)") == .command(.armNumber(digit)))
        }
    }

    @Test func escapeAndCmdQAreNotBound() throws {
        #expect(try action("Escape") == nil)
        #expect(try action("Cmd+Q") == nil)
    }

    @Test func strayShiftOrOptionFallsBackButCommandAndControlDoNot() throws {
        #expect(try action("Opt+Enter") == .command(.go))
        #expect(try action("Shift+B") == .command(.toggleCover(.black)))
        #expect(try action("Opt+Shift+Space") == .command(.playPause))
        #expect(try action("Shift+L") == .command(.toggleCover(.logo(2))))
        #expect(try action("Opt+Shift+Left") == .command(.parkArmed(by: -30)))
        #expect(try action("Cmd+B") == nil)
        #expect(try action("Ctrl+Shift+B") == nil)
    }

    @Test(arguments: [
        (#"{ "format": 1, "keys": { "Shift+Hyper": "go" } }"#, KeyMapError.unknownChord("Shift+Hyper"), "Shift+Hyper"),
        (#"{ "format": 1, "keys": { "B": "blackout" } }"#, .unknownAction(chord: "B", action: "blackout"), "blackout"),
        (
            #"{ "format": 1, "keys": { "Left": "seek:abc" } }"#, .unknownAction(chord: "Left", action: "seek:abc"),
            "seek:abc"
        ),
        (#"{ "format": 1, "keys": { "1": "arm" } }"#, .unknownAction(chord: "1", action: "arm"), "\"arm\""),
        (#"{ "format": 2, "keys": { "B": "hologram" } }"#, .unsupportedFormat(2), "format 2"),
        (#"{ "format": 1 }"#, .invalidJSON("missing \"keys\""), "keys"),
    ])
    func badKeymapThrowsNamingTheCulprit(json: String, error: KeyMapError, fragment: String) {
        #expect(throws: error) { try KeyMap(json: Data(json.utf8)) }
        #expect(error.description.contains(fragment))
    }
}
