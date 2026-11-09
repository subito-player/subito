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
            ("Ctrl+Opt+D", .toggleAdvanced),
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

private func chords(_ texts: String...) throws -> [KeyChord] {
    try texts.map { try #require(KeyChord($0)) }
}

@Suite struct KeyMapLookupTests {
    @Test func reverseLookupPutsTheMainKeyFirst() throws {
        let map = KeyMap.standard
        #expect(map.chords(for: .command(.go)) == (try chords("Enter", "KeypadEnter")))
        #expect(map.chords(for: .command(.armPrevious)) == (try chords("Up", "KeypadMinus")))
        #expect(map.chords(for: .command(.armNext)) == (try chords("Down", "KeypadPlus")))
        #expect(map.chords(for: .command(.toggleCover(.logo(2)))) == (try chords("Shift+L")))
        #expect(map.chords(for: .command(.seekLive(by: 7))) == [])
    }

    @Test func orderDoesNotDependOnTheFile() throws {
        let a = try KeyMap(
            json: Data(#"{ "format": 1, "keys": { "Shift+G": "go", "KeypadEnter": "go", "G": "go" } }"#.utf8))
        let b = try KeyMap(
            json: Data(#"{ "format": 1, "keys": { "G": "go", "KeypadEnter": "go", "Shift+G": "go" } }"#.utf8))
        #expect(a.chords(for: .command(.go)) == (try chords("G", "Shift+G", "KeypadEnter")))
        #expect(b.chords(for: .command(.go)) == a.chords(for: .command(.go)))
    }

    @Test func everyBoundActionIsListedOnce() {
        let actions = KeyMap.standard.actions
        #expect(actions.count == 28)
        #expect(actions.filter { $0 == .command(.go) }.count == 1)
        #expect(actions.contains(.toggleAdvanced))
    }

    @Test func chordNameReadsBackAndLabelShowsArrows() throws {
        let chord = KeyChord(key: "Right", modifiers: [.shift, .option, .command, .control])
        #expect(chord.name == "Ctrl+Cmd+Opt+Shift+Right")
        #expect(KeyChord(chord.name) == chord)
        #expect(chord.label(.en) == "Ctrl+Cmd+Opt+Shift+→")
        #expect(try #require(KeyChord("Shift+L")).label(.hu) == "Shift+L")
    }

    @Test func labelsNameKeysInTheOperatorsLanguage() throws {
        let labels = { (text: String, lang: Lang) in try #require(KeyChord(text)).label(lang) }
        #expect(try labels("Space", .hu) == "Szóköz")
        #expect(try labels("Space", .en) == "Space")
        #expect(try labels("KeypadEnter", .hu) == "Num Enter")
        #expect(try labels("KeypadEnter", .en) == "Keypad Enter")
        #expect(try labels("Shift+PageDown", .hu) == "Shift+Page Down")
        #expect(try labels("Escape", .en) == "Esc")
    }

    @Test func advancedViewAvoidsTheDockShortcut() throws {
        #expect(KeyMap.standard.chords(for: .toggleAdvanced) == (try chords("Ctrl+Opt+D")))
        #expect(try KeyMap.standard.action(for: #require(KeyChord("Cmd+Opt+D"))) == nil)
    }

    @Test(arguments: [("?", "Shift+/"), ("Opt+!", "Opt+Shift+1"), (":", "Shift+;")])
    func shiftedCharactersAreRejectedWithTheChordToUse(text: String, use: String) {
        let json = #"{ "format": 1, "keys": { "Enter": "go", "\#(text)": "black" } }"#
        #expect(throws: KeyMapError.shiftedKey(chord: text, use: use)) { try KeyMap(json: Data(json.utf8)) }
        #expect(KeyMapError.shiftedKey(chord: text, use: use).description.contains(use))
    }
}

@Suite struct KeyMapFileTests {
    @Test func missingFileGetsTheDefaultWrittenAndLoaded() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("support/keymap.json")
            #expect(try KeyMap.installDefault(at: url))
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text == KeyMap.defaultJSON + "\n")
            let (map, error) = KeyMap.load(from: url)
            #expect(error == nil)
            #expect(map.chords(for: .command(.go)) == KeyMap.standard.chords(for: .command(.go)))
        }
    }

    @Test func anEditedFileIsNeverOverwritten() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("keymap.json")
            let edited = #"{ "format": 1, "keys": { "PageDown": "go", "KeypadEnter": "go" } }"#
            try write(edited, to: url)
            #expect(try KeyMap.installDefault(at: url) == false)
            #expect(try String(contentsOf: url, encoding: .utf8) == edited)
            let (map, error) = KeyMap.load(from: url)
            #expect(error == nil)
            #expect(map.chords(for: .command(.go)) == (try chords("PageDown", "KeypadEnter")))
            #expect(try map.action(for: #require(KeyChord("Enter"))) == nil)
        }
    }

    @Test func brokenFileFallsBackToTheDefaultAndNamesTheCulprit() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("keymap.json")
            try write(#"{ "format": 1, "keys": { "Enter": "go", "B": "blackout" } }"#, to: url)
            let (map, error) = KeyMap.load(from: url)
            #expect(error == .unknownAction(chord: "B", action: "blackout"))
            #expect(try map.action(for: #require(KeyChord("B"))) == .command(.toggleCover(.black)))
            #expect(try map.action(for: #require(KeyChord("Enter"))) == .command(.go))
        }
    }

    @Test func aMapWithoutGoFallsBackToTheDefault() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("keymap.json")
            try write(#"{ "format": 1, "keys": { "B": "black", "Space": "playPause" } }"#, to: url)
            let (map, error) = KeyMap.load(from: url)
            #expect(error == .noGo)
            #expect(map.chords(for: .command(.go)) == (try chords("Enter", "KeypadEnter")))
        }
    }

    @Test func unreadableFileFallsBackToTheDefault() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("keymap.json")
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let (map, error) = KeyMap.load(from: url)
            guard case .unreadable? = error else {
                Issue.record("expected unreadable, got \(String(describing: error))")
                return
            }
            #expect(error?.description.hasPrefix("keymap.json cannot be read") == true)
            #expect(map.chords(for: .toggleAdvanced) == (try chords("Ctrl+Opt+D")))
        }
    }

    @Test func fileStillMissingAfterAFailedInstallMeansTheDefault() throws {
        try withTempDir { dir in
            let (map, error) = KeyMap.load(from: dir.appendingPathComponent("keymap.json"))
            #expect(error == nil)
            #expect(map.actions.count == KeyMap.standard.actions.count)
        }
    }
}
