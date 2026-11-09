import Foundation
import Testing

@testable import CueCore

private func map(_ keys: String) throws -> KeyMap {
    try KeyMap(json: Data(#"{ "format": 1, "keys": { \#(keys) } }"#.utf8))
}

private func row(_ sections: [CheatSheet.Section], keys: [String]) -> CheatSheet.Row? {
    sections.flatMap(\.rows).first { $0.keys == keys }
}

@Suite struct CheatSheetTests {
    @Test(arguments: Lang.allCases)
    func everyDefaultKeyAndActionIsPrinted(lang: Lang) {
        let html = CheatSheet.html(keyMap: .standard, lang: lang)
        let rows = CheatSheet.sections(keyMap: .standard, lang: lang).flatMap(\.rows)
        for action in KeyMap.standard.actions {
            for chord in KeyMap.standard.chords(for: action) {
                #expect(html.contains("<kbd>\(CheatSheet.escape(chord.label(lang)))</kbd>"), "\(chord.name)")
                #expect(rows.contains { $0.keys.contains(chord.label(lang)) }, "\(chord.name)")
            }
        }
        // Five show rows, twelve moving rows (digits share one), mute, quit, Esc and the Advanced view.
        #expect(rows.count == 21)
        #expect(Set(rows.map(\.label)).count == rows.count)
        #expect(html.hasPrefix("<!doctype html>\n<html lang=\"\(lang.rawValue)\">"))
        #expect(html.hasSuffix("</html>\n"))
    }

    @Test func groupsAndOrderFollowTheShow() {
        let sections = CheatSheet.sections(keyMap: .standard, lang: .en)
        #expect(sections.map(\.title) == ["Show", "Moving", "Sound and safety"])
        #expect(sections[0].rows.map(\.keys) == [["Enter", "Keypad Enter"], ["Space"], ["B"], ["L"], ["Shift+L"]])
        #expect(sections[0].rows[0].label == "GO: start the armed item")
        #expect(
            sections[1].rows.map(\.keys).prefix(5) == [
                ["←"], ["→"], ["Shift+←"], ["Shift+→"], ["Home"],
            ])
        #expect(sections[1].rows.last?.keys == (0...9).map(String.init))
        #expect(sections[2].rows.map(\.keys) == [["M"], ["Cmd+Q"], ["Esc"], ["Ctrl+Opt+D"]])
    }

    @Test func aRemappedGoPrintsItsNewKey() throws {
        let remapped = try map(#""PageDown": "go", "KeypadEnter": "go", "B": "black""#)
        let html = CheatSheet.html(keyMap: remapped, lang: .hu)
        let sections = CheatSheet.sections(keyMap: remapped, lang: .hu)
        #expect(row(sections, keys: ["Page Down", "Num Enter"])?.label == "GO: indul az előkészített elem")
        #expect(html.contains("<kbd>Page Down</kbd> <kbd>Num Enter</kbd>"))
        #expect(!html.contains("<kbd>Enter</kbd>"))
        #expect(!html.contains("<kbd>Szóköz</kbd>"))
    }

    @Test func escapeIsListedAsDoingNothingOnlyWhileUnbound() throws {
        #expect(row(CheatSheet.sections(keyMap: .standard, lang: .en), keys: ["Esc"])?.label == "Does nothing")
        let sections = CheatSheet.sections(keyMap: try map(#""Escape": "black""#), lang: .en)
        #expect(!sections.flatMap(\.rows).contains { $0.label == "Does nothing" })
        #expect(row(sections, keys: ["Esc"])?.label == "Black cover on / off")
    }

    @Test func digitsOnOtherKeysSayWhichNumberTheyArm() throws {
        let sections = CheatSheet.sections(
            keyMap: try map(#""3": "arm:3", "F1": "arm:1", "Shift+F2": "arm:12""#), lang: .en)
        #expect(
            row(sections, keys: ["F1 (1)", "3", "Shift+F2 (12)"])?.label == "Arm a clip by its number (in this movie)")
    }

    @Test func otherSecondsReadAsTheirOwnRows() throws {
        let sections = CheatSheet.sections(
            keyMap: try map(#""PageUp": "seek:-2.5", "Opt+PageUp": "park:10""#), lang: .hu)
        #expect(row(sections, keys: ["Page Up"])?.label == "Élő klip: 2,5 mp vissza")
        #expect(row(sections, keys: ["Opt+Page Up"])?.label == "Következő klip indulópontja: 10 mp előre")
    }

    @Test func textIsEscapedForHTML() {
        #expect(CheatSheet.escape(#"<b> & "c""#) == "&lt;b&gt; &amp; &quot;c&quot;")
    }

    @Test func hungarianSheetNamesKeysInHungarian() {
        let sections = CheatSheet.sections(keyMap: .standard, lang: .hu)
        #expect(sections[0].rows.map(\.keys).prefix(2) == [["Enter", "Num Enter"], ["Szóköz"]])
        #expect(sections[1].rows.map(\.keys).contains(["↑", "Num -"]))
    }
}
