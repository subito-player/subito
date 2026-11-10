import Foundation

// One printable A4 page per language, built from the loaded key map so a remapped key prints as it works.
public enum CheatSheet {
    public struct Row: Equatable {
        public var label: String
        public var keys: [String]
    }

    public struct Section: Equatable {
        public var title: String
        public var rows: [Row]
    }

    private enum Group: Int, CaseIterable {
        case show, moving, safety
    }

    private struct Entry {
        var group: Group
        var order: Int
        var value: Double = 0
        var row: Row

        // 5 s back, 5 s forward, then 30 s back, 30 s forward.
        var rank: (Int, Int, Double, Double) {
            (group.rawValue, order, abs(value), value)
        }
    }

    public static func html(keyMap: KeyMap, lang: Lang) -> String {
        let words = Words(lang: lang)
        var body = ""
        for section in sections(keyMap: keyMap, lang: lang) {
            body += "<h2>\(escape(section.title))</h2>\n<table>\n"
            for row in section.rows {
                let keys = row.keys.map { "<kbd>\(escape($0))</kbd>" }.joined(separator: " ")
                body += "<tr><td class=\"keys\">\(keys)</td><td>\(escape(row.label))</td></tr>\n"
            }
            body += "</table>\n"
        }
        return """
            <!doctype html>
            <html lang="\(lang.rawValue)">
            <head>
            <meta charset="utf-8">
            <title>\(escape(words.title))</title>
            <style>
            @page { size: A4; margin: 12mm; }
            html, body { background: #fff; color: #000; }
            body { font: 18px/1.25 -apple-system, "Helvetica Neue", Arial, sans-serif; max-width: 186mm; margin: 0 auto; }
            h1 { font-size: 30px; margin: 0 0 2mm; }
            .note { margin: 0 0 3mm; }
            h2 { font-size: 20px; margin: 4mm 0 1mm; border-bottom: 2px solid #000; }
            table { width: 100%; border-collapse: collapse; }
            td { padding: 1mm 2mm 1mm 0; vertical-align: top; border-bottom: 1px solid #999; }
            td.keys { width: 45%; }
            kbd { font: 700 16px Menlo, monospace; border: 1.5px solid #000; border-radius: 4px; padding: 0 4px; }
            </style>
            </head>
            <body>
            <h1>\(escape(words.title))</h1>
            <p class="note">\(escape(words.note))</p>
            \(body)</body>
            </html>

            """
    }

    // The same rows feed the printable page and the in-app key list.
    public static func sections(keyMap: KeyMap, lang: Lang) -> [Section] {
        let words = Words(lang: lang)
        var entries: [Entry] = []
        var numbers: [(number: Int, chord: KeyChord)] = []
        for action in keyMap.actions {
            let chords = keyMap.chords(for: action)
            if case .command(.armNumber(let number)) = action {
                numbers += chords.map { (number, $0) }
                continue
            }
            let (group, order, value) = place(action)
            let row = Row(label: words.label(action), keys: chords.map { $0.label(lang) })
            entries.append(Entry(group: group, order: order, value: value, row: row))
        }
        if !numbers.isEmpty {
            let keys = numbers.sorted { $0.number < $1.number }.map { number, chord in
                chord.name == "\(number)" ? chord.name : "\(chord.label(lang)) (\(number))"
            }
            entries.append(Entry(group: .moving, order: 5, row: Row(label: words.armNumber, keys: keys)))
        }
        // Cmd+Q and Esc are fixed in the app; a key map that binds them gets its own row instead.
        if keyMap.action(for: KeyChord(key: "Q", modifiers: [.command])) == nil {
            entries.append(Entry(group: .safety, order: 1, row: Row(label: words.quit, keys: ["Cmd+Q"])))
        }
        if keyMap.action(for: KeyChord(key: "Escape")) == nil {
            entries.append(Entry(group: .safety, order: 2, row: Row(label: words.escape, keys: ["Esc"])))
        }
        entries.sort { $0.rank < $1.rank }
        return Group.allCases.compactMap { group in
            let rows = entries.filter { $0.group == group }.map(\.row)
            return rows.isEmpty ? nil : Section(title: words.title(group), rows: rows)
        }
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func place(_ action: KeyAction) -> (Group, Int, Double) {
        switch action {
        case .command(.go): (.show, 0, 0)
        case .command(.playPause): (.show, 1, 0)
        case .command(.toggleCover(.black)): (.show, 2, 0)
        case .command(.toggleCover(.logo(let number))): (.show, 3, Double(number))
        case .command(.seekLive(let delta)): (.moving, 0, delta)
        case .command(.restartLive): (.moving, 1, 0)
        case .command(.parkArmed(let delta)): (.moving, 2, delta)
        case .command(.armPrevious): (.moving, 3, 0)
        case .command(.armNext): (.moving, 4, 0)
        case .command(.toggleMute): (.safety, 0, 0)
        case .toggleAdvanced: (.safety, 3, 0)
        default: (.safety, 4, 0)
        }
    }

    // Two columns per line: Hungarian, then English.
    private struct Words {
        let lang: Lang

        private func pick(_ hu: String, _ en: String) -> String {
            lang == .hu ? hu : en
        }

        var title: String { pick("Puskalap", "Cheat sheet") }
        var note: String {
            pick(
                "A kivetítő csak billentyűre vált. Ami megerősítést kér: nyomd meg újra 3 mp-en belül.",
                "The projector changes only on a key press. Anything that asks to confirm: press again within 3 s.")
        }
        var armNumber: String {
            pick("Klip előkészítése a száma alapján (ebben a filmben)", "Arm a clip by its number (in this movie)")
        }
        var quit: String { pick("Kilépés: nyomd meg kétszer 3 mp-en belül", "Quit: press twice within 3 s") }
        var escape: String { pick("Nem csinál semmit", "Does nothing") }

        func title(_ group: Group) -> String {
            switch group {
            case .show: pick("Műsor", "Show")
            case .moving: pick("Mozgás", "Moving")
            case .safety: pick("Hang és biztonság", "Sound and safety")
            }
        }

        func label(_ action: KeyAction) -> String {
            switch action {
            case .toggleAdvanced: return pick("Haladó nézet (tulajdonosnak)", "Advanced view (owner)")
            case .command(let command): return label(command)
            }
        }

        private func label(_ command: Command) -> String {
            switch command {
            case .go: pick("GO: indul az előkészített elem", "GO: start the armed item")
            case .playPause: pick("Élő klip: lejátszás / megállítás", "Live clip: play / pause")
            case .toggleCover(.black): pick("Fekete takarás be / ki", "Black cover on / off")
            case .toggleCover(.logo(let number)):
                pick("\(number). logó takarás be / ki", "Logo \(number) cover on / off")
            case .seekLive(let delta) where delta < 0:
                pick("Élő klip: \(seconds(delta)) mp vissza", "Live clip: back \(seconds(delta)) s")
            case .seekLive(let delta):
                pick("Élő klip: \(seconds(delta)) mp előre", "Live clip: forward \(seconds(delta)) s")
            case .restartLive: pick("Élő klip: vissza az elejére", "Live clip: back to the start")
            case .parkArmed(let delta) where delta < 0:
                pick(
                    "Következő klip indulópontja: \(seconds(delta)) mp vissza",
                    "Next clip start point: back \(seconds(delta)) s")
            case .parkArmed(let delta):
                pick(
                    "Következő klip indulópontja: \(seconds(delta)) mp előre",
                    "Next clip start point: forward \(seconds(delta)) s")
            case .armPrevious: pick("Előző elem előkészítése", "Arm the previous item")
            case .armNext: pick("Következő elem előkészítése", "Arm the next item")
            case .armNumber: armNumber
            case .toggleMute:
                pick(
                    "Hang ki; bekapcsolás: nyomd meg kétszer 3 mp-en belül (csak próbán)",
                    "Sound off; on: press twice within 3 s (rehearsal only)")
            default: "\(command)"
            }
        }

        // Hungarian writes a decimal comma.
        private func seconds(_ delta: Double) -> String {
            let text = String(format: "%g", abs(delta))
            return lang == .hu ? text.replacingOccurrences(of: ".", with: ",") : text
        }
    }
}
