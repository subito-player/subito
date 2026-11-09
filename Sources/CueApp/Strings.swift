import CoreGraphics
import CueCore
import Foundation

enum Lang: String, CaseIterable {
    case hu, en

    private static let savedKey = "language"

    static var saved: Lang {
        UserDefaults.standard.string(forKey: savedKey).flatMap(Lang.init(rawValue:)) ?? .hu
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.savedKey)
    }
}

// Two columns per line: Hungarian, then English.
struct Strings {
    let lang: Lang

    private func pick(_ hu: String, _ en: String) -> String {
        lang == .hu ? hu : en
    }

    // --- Top bar ---
    var rehearsal: String { pick("Próba", "Rehearsal") }
    var concert: String { pick("Koncert", "Concert") }
    var noShow: String { pick("Nincs betöltött műsor", "No show loaded") }
    var noProjector: String { pick("NINCS PROJEKTOR", "NO PROJECTOR") }
    var mirroring: String {
        pick("Tükrözés: a projektor a laptop képét mutatja", "Mirroring: the projector shows the laptop screen")
    }
    var muted: String { pick("NÉMÍTVA", "MUTED") }
    var lastKey: String { pick("Utolsó gomb", "Last key") }
    var output: String { pick("Kimenet", "Output") }
    var automatic: String { pick("Automatikus", "Automatic") }
    var noExternalDisplay: String { pick("Nincs külső kijelző", "No external display") }
    var open: String { pick("Megnyitás", "Open") }
    var openMessage: String {
        pick(
            "Koncert (.concert.json), film (.movie.json) vagy klipeket tartalmazó mappa",
            "A concert (.concert.json), a movie (.movie.json) or a folder of clips")
    }

    func display(_ name: String?, id: CGDirectDisplayID) -> String {
        name ?? pick("Kijelző \(id)", "Display \(id)")
    }

    func confirmOutput(_ name: String) -> String {
        pick("Kattints újra: kimenet → \(name)", "Click again: output → \(name)")
    }

    func projector(_ name: String, hz: Double) -> String {
        let label = pick("Projektor: \(name)", "Projector: \(name)")
        guard hz > 0 else { return label }
        return label + String(format: hz == hz.rounded() ? " · %.0f Hz" : " · %.2f Hz", hz)
    }

    func audioOn(device: String?) -> String {
        let label = pick("HANG BE", "AUDIO ON")
        return device.map { "\(label) → \($0)" } ?? label
    }

    // --- Banners and notices ---
    var focusLost: String {
        pick("A BILLENTYŰK NEM AZ APPHOZ MENNEK. KATTINTS IDE.", "KEYS ARE NOT REACHING THE APP. CLICK HERE.")
    }
    var filePicker: String {
        pick("Fájlválasztó nyitva: a billentyűk a panelbe mennek", "File picker open: keys go to the picker")
    }
    var noProjectorBanner: String {
        pick(
            "NINCS PROJEKTOR. ELLENŐRIZD A KÁBELT. A LEJÁTSZÁS NEM ÁLL LE.",
            "NO PROJECTOR. CHECK THE CABLE. PLAYBACK KEEPS RUNNING.")
    }

    func notice(_ notice: Notice) -> String {
        switch notice {
        case .nothingArmed:
            pick("Nincs semmi előkészítve", "Nothing armed")
        case .armedNotReady:
            pick("A következő klip még töltődik", "Next clip is still loading")
        case .soundLockedInConcert:
            pick("Koncert módban a hang mindig ki van kapcsolva", "Sound is always off in concert mode")
        case .confirmUnmute:
            pick("Nyomd meg újra az M-et a hang bekapcsolásához (3 mp)", "Press M again to turn sound on (3 s)")
        case .confirmMode(let mode):
            pick("Kattints újra: váltás \(name(mode)) módra (3 mp)", "Click again to switch to \(name(mode)) (3 s)")
        case .confirmQuit:
            pick("Nyomd meg újra a Cmd+Q-t a kilépéshez (3 mp)", "Press Cmd+Q again to quit (3 s)")
        }
    }

    func name(_ mode: Mode) -> String {
        mode == .concert ? concert : rehearsal
    }

    // --- Previews and progress ---
    var live: String { pick("ÉLŐ", "LIVE") }
    var next: String { pick("KÖVETKEZŐ", "NEXT") }
    var nothing: String { pick("semmi", "nothing") }
    var covered: String { pick("TAKARVA", "COVERED") }
    var running: String { pick("fut", "running") }
    var paused: String { pick("áll", "paused") }
    var loading: String { pick("töltődik", "loading") }
    var toPlannedEnd: String { pick("tervezett végéig", "to planned end") }
    var toClipEnd: String { pick("klip végéig", "to clip end") }

    // --- Cues ---
    var black: String { pick("Fekete", "Black") }
    var logo: String { pick("Logó", "Logo") }
    var breakTitle: String { pick("Szünet", "Intermission") }
    var minutes: String { pick("perc", "min") }

    func number(_ cue: Cue) -> String {
        guard case .clip(let clip, _) = cue.kind, let number = clip.resolvedNumber else { return "" }
        return String(format: "%02ld", number)
    }

    func label(_ cue: Cue) -> String {
        switch cue.kind {
        case .clip(let clip, _): clip.resolvedTitle
        case .black: black
        case .breakScreen(let item): "\(breakTitle) \(String(format: "%g", item.minutes)) \(minutes)"
        case .logo(let number): "\(logo) \(number)"
        }
    }

    func title(_ cue: Cue) -> String {
        [number(cue), label(cue)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // --- Buttons ---
    var go: String { pick("GO", "GO") }
    var play: String { pick("Lejátszás", "Play") }
    var restart: String { pick("Elejére", "Restart") }
    var sound: String { pick("Hang", "Sound") }

    // --- Status line ---
    var allGood: String { pick("Minden rendben", "All good") }
    var noProjectorStatus: String { pick("Nincs projektor csatlakoztatva", "No projector connected") }

    func cannotPlay(_ cue: String, reason: String) -> String {
        pick("\(cue) nem játszható le: \(reason)", "\(cue) cannot play: \(reason)")
    }

    func pictureUnconfirmed(_ cue: String) -> String {
        pick("\(cue): a kép nincs megerősítve, a GO működik", "\(cue): picture not confirmed, GO still works")
    }

    var checking: String { pick("Ellenőrzés…", "Checking…") }

    func clipsCannotPlay(_ count: Int) -> String {
        pick("\(count) klip nem játszható", count == 1 ? "1 clip cannot play" : "\(count) clips cannot play")
    }

    func warnings(_ count: Int) -> String {
        pick("\(count) figyelmeztetés", count == 1 ? "1 warning" : "\(count) warnings")
    }

    var recoverySkipped: String {
        pick("Helyreállítás kihagyva ismételt összeomlás után", "Recovery skipped after repeated crashes")
    }

    func recovered(_ cue: Cue?, at position: Double) -> String {
        guard let cue else { return pick("Helyreállítva.", "Recovered.") }
        guard case .clip = cue.kind else {
            return pick("Helyreállítva. Élő volt: \(title(cue)).", "Recovered. Was live: \(title(cue)).")
        }
        let name = number(cue).isEmpty ? label(cue) : number(cue)
        let time = clockText(position)
        return pick(
            "Helyreállítva. \(Self.article(name)) \(name) ment \(time)-\(Self.at(position)).",
            "Recovered. Was playing \(name) at \(time).")
    }

    func problem(_ problem: Problem) -> String {
        switch problem {
        case .show(let reason): pick("A műsor nem nyitható meg: \(reason)", "Cannot open the show: \(reason)")
        case .keyMap(let reason): pick("A billentyűkiosztás hibás: \(reason)", "The key map is broken: \(reason)")
        }
    }

    // --- Preflight panel ---
    var preflight: String { pick("Ellenőrzés", "Preflight check") }
    var close: String { pick("Bezárás", "Close") }
    var showSection: String { pick("Műsor", "Show") }
    var systemSection: String { pick("Rendszer", "System") }
    var byHand: String { pick("Kézzel ellenőrizd", "Check by hand") }

    func everyClipPlays(_ count: Int) -> String {
        pick("Minden klip lejátszható (\(count))", "Every clip plays (\(count))")
    }

    func manual(_ check: ManualCheck) -> String {
        switch check {
        case .focus: pick("Ne zavarjanak (Fókusz) bekapcsolva", "Focus / Do Not Disturb on")
        case .updates: pick("Automatikus frissítés kikapcsolva", "Automatic updates off")
        case .wallpaper: pick("Fekete háttérkép minden kijelzőn", "Black wallpaper on every display")
        case .backup: pick("Tartalék gép kész", "Backup rig ready")
        }
    }

    func finding(_ finding: Finding) -> String {
        switch (finding.kind, finding.severity) {
        case (.fileMissing, _): pick("A fájl hiányzik", "File is missing")
        case (.notPlayable, _): pick("Nem játszható le", "Cannot be played")
        case (.noVideo, _): pick("Nincs benne kép", "Has no picture")
        case (.size, _): pick("Nem 1920x1080, de lejátszható", "Not 1920x1080, still plays")
        case (.frameRate, _): pick("Nem 23,976 fps, de lejátszható", "Not 23.976 fps, still plays")
        case (.length, _):
            pick("A hossza eltér a tervezett vég + ráhagyás összegétől", "Length differs from planned end + tail")
        case (.plannedEnd, _): pick("A tervezett vég a klip vége után van", "Planned end is after the clip ends")
        case (.logo, _):
            pick("A logó nem tölthető be, helyette fekete lesz", "Logo cannot be loaded, shows black instead")
        case (.projector, .ok): pick("Projektor csatlakoztatva", "Projector connected")
        case (.projector, _): pick("Nincs projektor", "No projector")
        case (.mirrored, _): mirroring
        case (.refreshRate, _): pick("Frissítési gyakoriság", "Refresh rate")
        case (.betterRefreshRate, _):
            pick(
                "Jobb frissítési gyakoriság is van: Rendszerbeállítások > Kijelzők",
                "A better refresh rate is available: System Settings > Displays")
        case (.power, .ok): pick("Töltő csatlakoztatva", "Power adapter connected")
        case (.power, _): pick("Akkumulátorról megy, dugd be a töltőt", "Running on battery, plug in the power adapter")
        case (.spaces, .ok): pick("A kijelzők külön Spaces-ben vannak", "Displays have separate Spaces")
        case (.spaces, _):
            pick(
                "A kijelzők nincsenek külön Spaces-ben: Rendszerbeállítások > Asztal és Dock",
                "Displays do not have separate Spaces: System Settings > Desktop & Dock")
        case (.sound, .ok): pick("Hangkimenet", "Sound output")
        case (.sound, _):
            pick("A hang egy kijelzőre megy (HDMI/DisplayPort)", "Sound goes to a display (HDMI/DisplayPort)")
        }
    }

    // --- Last key ---
    func action(_ result: KeyResult) -> String {
        switch result {
        case .nothing: nothing
        case .advanced: pick("Haladó nézet (még nincs kész)", "Advanced view (not built yet)")
        case .command(let command): action(command)
        }
    }

    private func action(_ command: Command) -> String {
        switch command {
        case .go: go
        case .playPause: pick("Lejátszás/megállítás", "Play/pause")
        case .toggleCover(.black): black
        case .toggleCover(.logo(let number)): "\(logo) \(number)"
        case .seekLive(let delta): pick("Ugrás \(signed(delta)) mp", "Seek \(signed(delta)) s")
        case .restartLive: restart
        case .parkArmed(let delta): pick("Következő \(signed(delta)) mp", "Next \(signed(delta)) s")
        case .parkArmedAt(let time): pick("Következő @ \(clockText(time))", "Next @ \(clockText(time))")
        case .armNext: pick("Előkészítés: következő", "Arm next")
        case .armPrevious: pick("Előkészítés: előző", "Arm previous")
        case .armNumber(let number): pick("Előkészítés: \(number). klip", "Arm clip \(number)")
        case .arm: pick("Előkészítés", "Arm")
        case .toggleMute: sound
        case .requestMode: pick("Módváltás", "Mode switch")
        case .requestQuit: pick("Kilépés", "Quit")
        case .armedReady, .liveEnded: ""
        }
    }

    private func signed(_ seconds: Double) -> String {
        String(format: "%+g", seconds)
    }

    // "Az" before a vowel sound: a vowel letter, or 5 (öt, ötven).
    private static func article(_ word: String) -> String {
        guard let first = word.lowercased().first else { return "A" }
        return "aáeéiíoóöőuúüű5".contains(first) ? "Az" : "A"
    }

    // -nál after a back-vowel number word for the seconds (három, hat, nyolc, nulla, húsz, harminc), else -nél.
    private static func at(_ position: Double) -> String {
        let seconds = position.isFinite ? Int(min(max(position, 0), 359_999)) % 60 : 0
        let back = [3, 6, 8].contains(seconds % 10) || (seconds % 10 == 0 && [0, 2, 3].contains(seconds / 10))
        return back ? "nál" : "nél"
    }
}

// m:ss, clamped so a NaN or a huge value can never trap Int().
func clockText(_ seconds: Double, rounding rule: FloatingPointRoundingRule = .down) -> String {
    let value = seconds.isFinite ? min(max(seconds.rounded(rule), 0), 359_999) : 0
    let total = Int(value)
    return String(format: "%ld:%02ld", total / 60, total % 60)
}
