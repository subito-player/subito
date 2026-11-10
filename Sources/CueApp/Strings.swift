import CoreGraphics
import CueCore
import Foundation

extension Lang {
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
    // Texts naming a key read it from here, so a remapped key is named right.
    var keyMap = KeyMap.standard

    private func pick(_ hu: String, _ en: String) -> String {
        lang == .hu ? hu : en
    }

    // --- Top bar ---
    var rehearsal: String { pick("Próba", "Rehearsal") }
    var concert: String { pick("Koncert", "Concert") }
    var noShow: String { pick("Nincs betöltött műsor", "No show loaded") }
    var emptyConcert: String {
        pick(
            "Üres koncert. Húzz ide egy filmet (.movie.json vagy klipmappa), vagy Szerkesztés, majd + Film.",
            "Empty concert. Drag a movie here (.movie.json or a clip folder), or Edit, then + Movie.")
    }
    var emptyMovie: String {
        pick(
            "Üres film. Húzz ide klipeket, vagy Szerkesztés, majd + Klip.",
            "Empty movie. Drag clips here, or Edit, then + Clip.")
    }
    var noProjector: String { pick("NINCS PROJEKTOR", "NO PROJECTOR") }
    var mirroring: String {
        pick("Tükrözés: a projektor a laptop képét mutatja", "Mirroring: the projector shows the laptop screen")
    }
    var muted: String { pick("NÉMÍTVA", "MUTED") }
    var lastKey: String { pick("Utolsó gomb", "Last key") }
    var keys: String { pick("Billentyűk", "Keys") }
    var output: String { pick("Kimenet", "Output") }
    var automatic: String { pick("Automatikus", "Automatic") }
    var noExternalDisplay: String { pick("Nincs külső kijelző", "No external display") }
    var view: String { pick("Nézet", "View") }
    var open: String { pick("Megnyitás", "Open") }
    var openMessage: String {
        pick(
            "Koncert (.concert.json), film (.movie.json) vagy klipeket tartalmazó mappa",
            "A concert (.concert.json), a movie (.movie.json) or a folder of clips")
    }
    var newMovie: String { pick("Új film", "New movie") }
    var newMovieMessage: String {
        pick(
            "Klipeket tartalmazó mappa, vagy hozz létre egy új, üres mappát",
            "A folder of clips, or create a new empty folder")
    }
    var newConcert: String { pick("Új koncert", "New concert") }
    var newConcertMessage: String { pick("Az új koncert neve és helye", "Name and place of the new concert") }
    var newConcertName: String { pick("Koncert", "Concert") }
    var create: String { pick("Létrehozás", "Create") }

    func display(_ name: String?, id: CGDirectDisplayID) -> String {
        name ?? pick("Kijelző \(id)", "Display \(id)")
    }

    func confirmOutput(_ name: String) -> String {
        pick("Kattints újra: kimenet → \(name)", "Click again: output → \(name)")
    }

    func presentation(_ presentation: OutputPresentation) -> String {
        switch presentation {
        case .fullscreen: pick("Teljes képernyő", "Fullscreen")
        case .window: pick("Ablakban", "Window")
        case .off: pick("Kikapcsolva", "Off")
        }
    }

    func confirmPresentation(_ presentation: OutputPresentation) -> String {
        pick(
            "Kattints újra: nézet → \(self.presentation(presentation))",
            "Click again: view → \(self.presentation(presentation))")
    }

    func outputWindowTitle(_ app: String) -> String { pick("\(app): kimenet", "\(app): output") }

    func projector(_ name: String, hz: Double) -> String {
        let label = pick("Projektor: \(name)", "Projector: \(name)")
        guard hz > 0 else { return label }
        return label + String(format: hz == hz.rounded() ? " · %.0f Hz" : " · %.2f Hz", hz)
    }

    func audioOn(device: String?) -> String {
        let label = pick("HANG BE", "AUDIO ON")
        return device.map { "\(label) → \($0)" } ?? label
    }

    // --- Menu bar ---
    func quit(_ app: String) -> String { pick("Kilépés: \(app)", "Quit \(app)") }
    var cut: String { pick("Kivágás", "Cut") }
    var copy: String { pick("Másolás", "Copy") }
    var paste: String { pick("Beillesztés", "Paste") }
    var selectAll: String { pick("Az összes kijelölése", "Select All") }

    // --- Banners and notices ---
    var focusLost: String {
        pick("A BILLENTYŰK NEM AZ APPHOZ MENNEK. KATTINTS IDE.", "KEYS ARE NOT REACHING THE APP. CLICK HERE.")
    }
    var filePicker: String {
        pick("Fájlválasztó nyitva: a billentyűk a panelbe mennek", "File picker open: keys go to the picker")
    }
    var typing: String { pick("Gépelés: a billentyűk a mezőbe mennek", "Typing: keys go to the field") }
    var concertBanner: String { pick("KONCERT", "CONCERT") }
    var unlockedBanner: String { pick("KONCERT · SZERKESZTÉS FELOLDVA", "CONCERT · EDITING UNLOCKED") }
    var unlockEditing: String { pick("Szerkesztés feloldása", "Unlock editing") }
    var lock: String { pick("Zárolás", "Lock") }

    func confirmDelete(_ name: String) -> String {
        pick("Kattints újra a törléshez: \(name) (3 mp)", "Click again to delete \(name) (3 s)")
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
            pick(
                "A hang bekapcsolásához nyomd meg újra: \(key(for: .command(.toggleMute))) (3 mp)",
                "Press \(key(for: .command(.toggleMute))) again to turn sound on (3 s)")
        case .confirmMode(let mode):
            pick("Kattints újra: váltás \(name(mode)) módra (3 mp)", "Click again to switch to \(name(mode)) (3 s)")
        case .confirmUnlock:
            pick("Kattints újra a szerkesztés feloldásához (3 mp)", "Click again to unlock editing (3 s)")
        case .confirmQuit:
            pick("Nyomd meg újra a Cmd+Q-t a kilépéshez (3 mp)", "Press Cmd+Q again to quit (3 s)")
        case .confirmQuitClick:
            pick("Koncert: a kilépéshez kattints ide (5 mp)", "Concert: click here to quit (5 s)")
        }
    }

    var quitTarget: String { pick("KILÉPÉS", "QUIT") }

    func key(_ chord: KeyChord) -> String {
        chord.label(lang)
    }

    func key(for action: KeyAction) -> String {
        keyMap.chords(for: action).first.map(key) ?? "-"
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
        case .breakScreen(let item): "\(item.text ?? breakTitle) \(String(format: "%g", item.minutes)) \(minutes)"
        case .logo(let number): "\(logo) \(number)"
        }
    }

    func title(_ cue: Cue) -> String {
        [number(cue), label(cue)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    // --- Editor ---
    var edit: String { pick("Szerkesztés", "Edit") }
    var addClip: String { pick("+ Klip", "+ Clip") }
    var addBlack: String { pick("+ Fekete", "+ Black") }
    var addBreak: String { pick("+ Szünet", "+ Break") }
    var addLogo: String { pick("+ Logó", "+ Logo") }
    var addMovie: String { pick("+ Film", "+ Movie") }
    var add: String { pick("Hozzáadás", "Add") }
    var addClipsMessage: String { pick("Videofájlok a filmbe", "Video files for the movie") }
    var addMovieMessage: String {
        pick("Film (.movie.json) vagy klipeket tartalmazó mappa", "A movie (.movie.json) or a folder of clips")
    }
    var concertTitle: String { pick("Koncert címe", "Concert title") }
    var movieTitle: String { pick("Film címe", "Movie title") }
    var clipTitle: String { pick("Cím", "Title") }
    var brief: String { pick("Instrukció", "Brief") }
    var briefPlaceholder: String { pick("pl. GO a karmester intésére", "e.g. GO on the conductor's upbeat") }
    var plannedEnd: String { pick("Tervezett vég", "Planned end") }
    var tail: String { pick("Ráhagyás", "Tail") }
    var breakText: String { pick("Szöveg", "Text") }
    var breakMinutes: String { pick("Perc", "Minutes") }
    var countdown: String { pick("Visszaszámlálás", "Countdown") }
    var logoNumber: String { pick("Logó", "Logo") }
    var noLogos: String {
        pick(
            "Ennek a műsornak nincs logója (a koncert logos listája üres)",
            "This show has no logos (the concert's logo list is empty)")
    }
    var nothingToSet: String { pick("Nincs mit beállítani", "Nothing to set") }
    var logoFile: String { pick("Kép vagy videó…", "Image or video…") }
    var noLogoFile: String { pick("nincs fájl", "no file") }
    var choose: String { pick("Kiválasztás", "Choose") }
    var movieHasNoLogos: String {
        pick(
            "Önálló filmnek nincs logója, a logók a koncerthez tartoznak",
            "A single movie has no logos, a concert does")
    }

    func logoFileMessage(_ number: Int) -> String {
        pick(
            "Logó \(number): kép, vagy hang nélkül ismétlődő videó",
            "Logo \(number): an image, or a video that loops silently")
    }

    func editNotice(_ notice: EditNotice) -> String {
        switch notice {
        case .refused(.liveItemLocked):
            pick("Az élő elem nem mozgatható és nem törölhető", "The live item cannot be moved or deleted")
        case .refused(.movieInMovie): pick("Filmbe nem tehető film", "A movie cannot go inside a movie")
        case .refused(.clipInConcert): pick("Klip csak filmbe kerülhet", "Clips go inside a movie")
        case .refused(.noSuchItem): pick("Ez az elem már nincs meg", "That item is gone")
        case .selectMovie:
            pick(
                "Jelölj ki egy sort abban a filmben, ahova a klip kerüljön",
                "Select a row in the movie the clip goes into")
        case .emptyTitle: pick("A cím nem lehet üres", "The title cannot be empty")
        case .invalidTime: pick("Érvénytelen idő, így írd: 3:25", "Invalid time, type it like 3:25")
        case .invalidMinutes: pick("Érvénytelen percszám", "Invalid number of minutes")
        case .cannotAddMovie(_, let error?):
            pick("A film nem adható hozzá: \(showError(error))", "Cannot add the movie: \(showError(error))")
        case .cannotAddMovie(let file, nil):
            pick("A film nem adható hozzá: \(file) nem olvasható", "Cannot add the movie: \(file) cannot be read")
        case .concertAsMovie: pick("Koncert nem tehető filmként egy koncertbe", "A concert can't be added as a movie")
        case .convertWhileRunning:
            pick("Állítsd meg vagy GO feketére a konvertálás előtt", "Pause, or GO to black, before converting")
        case .convertFailed(let file, let failure):
            pick(
                "A konvertálás nem sikerült: \(file): \(convertFailure(failure))",
                "Conversion failed: \(file): \(convertFailure(failure))")
        }
    }

    // --- Buttons ---
    var go: String { pick("GO", "GO") }
    var play: String { pick("Lejátszás", "Play") }
    var restart: String { pick("Elejére", "Restart") }
    var sound: String { pick("Hang", "Sound") }

    // --- Status line ---
    var allGood: String { pick("Minden rendben", "All good") }
    var noProjectorStatus: String { pick("Nincs projektor csatlakoztatva", "No projector connected") }

    // nil while fullscreen: only the rehearsal debug views need a word on the status line.
    func presentationNotice(_ presentation: OutputPresentation) -> String? {
        switch presentation {
        case .fullscreen: nil
        case .window:
            pick("Próba: a kimenet ablakban van, nem teljes képernyőn", "Rehearsal: output in a window, not fullscreen")
        case .off:
            pick(
                "Próba: a kimenet kikapcsolva, a projektor nem kap képet",
                "Rehearsal: output off, the projector gets no picture")
        }
    }

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
        case .show(_, let error?):
            pick("A műsor nem nyitható meg: \(showError(error))", "Cannot open the show: \(showError(error))")
        case .show(let file, nil):
            pick("A műsor nem nyitható meg: \(file) nem olvasható", "Cannot open the show: \(file) cannot be read")
        case .keyMap(let error):
            pick(
                "A billentyűkiosztás hibás, az alap billentyűk működnek: \(keyMapError(error))",
                "The key map is broken, the default keys work: \(keyMapError(error))")
        case .save(let file, let reason):
            pick("Nem sikerült menteni: \(file): \(reason)", "Cannot save \(file): \(reason)")
        }
    }

    func showError(_ error: ShowError) -> String {
        switch error {
        case .fileMissing(let url):
            pick(
                "\(url.lastPathComponent) hiányzik vagy nem olvasható",
                "\(url.lastPathComponent) is missing or unreadable")
        case .invalidJSON(let file, _):
            pick("\(file.lastPathComponent) hibás, nem olvasható be", "\(file.lastPathComponent) is not valid")
        case .unsupportedFormat(let file, let format):
            pick(
                "\(file.lastPathComponent) \(format). formátumú, ez a verzió csak a(z) \(currentFormat). formátumot olvassa",
                "\(file.lastPathComponent) uses format \(format), this version reads format \(currentFormat)")
        case .movieContainsMovie(let file):
            pick(
                "\(file.lastPathComponent) film, de egy másik filmet tartalmaz",
                "\(file.lastPathComponent) is a movie but contains another movie")
        case .concertHasClip(let file):
            pick(
                "\(file.lastPathComponent) koncert, de klip van benne; a klipek filmbe kerülnek",
                "\(file.lastPathComponent) is a concert but contains a clip; clips go inside a movie")
        case .movieFileMissing(let concert, let path):
            pick(
                "\(concert.lastPathComponent) a(z) \(path) filmre hivatkozik, ami nem létezik",
                "\(concert.lastPathComponent) refers to \(path), which does not exist")
        }
    }

    func keyMapError(_ error: KeyMapError) -> String {
        switch error {
        case .invalidJSON: pick("a keymap.json nem olvasható be", "keymap.json is not valid")
        case .unreadable: pick("a keymap.json nem nyitható meg", "keymap.json cannot be read")
        case .unsupportedFormat(let format):
            pick(
                "a keymap.json \(format). formátumú, ez a verzió csak a(z) \(KeyMap.format). formátumot olvassa",
                "keymap.json uses format \(format), this version reads format \(KeyMap.format)")
        case .unknownChord(let chord): pick("ismeretlen billentyű: \(chord)", "unknown key \(chord)")
        case .unknownAction(let chord, let action):
            pick("\(chord): ismeretlen művelet: \(action)", "\(chord) has an unknown action \(action)")
        case .shiftedKey(let chord, let use):
            pick(
                "\(chord) csak Shifttel írható, ezt írd helyette: \(use)", "\(chord) needs Shift, write \(use) instead")
        case .noGo: pick("nincs benne GO billentyű", "it has no key for GO")
        }
    }

    func loadFailure(_ failure: LoadFailure) -> String {
        switch failure {
        case .cannotLoad: pick("a fájl nem tölthető be", "the file cannot be loaded")
        case .playbackFailed: pick("a lejátszás megszakadt", "playback failed")
        case .pictureUnconfirmed: pick("a kép nincs megerősítve", "picture not confirmed")
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

    var convert: String { pick("Konvertálás", "Convert") }
    var convertAll: String { pick("Mind konvertálása", "Convert all") }
    var cancel: String { pick("Mégse", "Cancel") }
    var cancelAll: String { pick("Mind leállítása", "Cancel all") }
    var convertNeedsFFmpeg: String {
        pick("A konvertáláshoz ffmpeg kell (Homebrew vagy Nix)", "Converting needs ffmpeg (Homebrew or Nix)")
    }

    func converting(_ cue: String) -> String {
        pick("Konvertálás: \(cue)…", "Converting \(cue)…")
    }

    func conversion(_ phase: Converter.Phase, downloads: Bool) -> String {
        switch phase {
        case .waiting:
            return pick("Sorra vár", "Waiting")
        case .preparing:
            guard downloads else { return pick("Előkészítés…", "Preparing…") }
            return pick(
                "Előkészítés… (első alkalommal letölti az ffmpeget)", "Preparing… (the first run downloads ffmpeg)")
        case .running(let step, let fraction):
            let name = step == .remux ? pick("Átcsomagolás", "Repackaging") : pick("Újrakódolás", "Re-encoding")
            return fraction.map { name + String(format: " %.0f%%", $0 * 100) } ?? name + "…"
        }
    }

    func convertFailure(_ failure: Conversion.Failure) -> String {
        switch failure {
        case .cannotStart: pick("az ffmpeg nem indult el", "ffmpeg did not start")
        case .ffmpegFailed: pick("az ffmpeg nem tudta átalakítani", "ffmpeg could not convert it")
        case .stillNotPlayable: pick("az átalakított fájl sem játszható le", "the converted file does not play either")
        case .cannotSave: pick("a klip mappájába nem menthető új fájl", "cannot save a new file in the clip's folder")
        case .ffmpegMissing: pick("ffmpeg kell hozzá (Homebrew vagy Nix)", "it needs ffmpeg (Homebrew or Nix)")
        case .diskFull: pick("nincs elég szabad hely a lemezen", "not enough free disk space")
        }
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
        case (.logoNumber, _):
            pick(
                "Nincs ilyen sorszámú logó a műsorban, helyette fekete lesz",
                "The show has no logo with this number, shows black instead")
        case (.emptyShow, _): pick("A műsor üres", "The show has no cues")
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

    // --- Advanced view ---
    var advanced: String { pick("HALADÓ", "ADVANCED") }
    var version: String { pick("Verzió", "Version") }
    var memory: String { pick("Memória", "Memory") }
    var cheatSheet: String { pick("Puskalap", "Cheat sheet") }
    var openKeyMap: String { pick("Billentyűkiosztás megnyitása", "Open key map") }
    var openLogFolder: String { pick("Naplómappa megnyitása", "Open log folder") }
    var stressTest: String { pick("Stresszteszt", "Stress test") }
    var switches: String { pick("váltás", "switches") }
    var start: String { pick("Indítás", "Start") }
    var stop: String { pick("Leállítás", "Stop") }
    var stressRunning: String { pick("fut, bármelyik billentyű leállítja", "running, any key stops it") }
    var stressDone: String { pick("kész", "done") }
    var stressStopped: String { pick("leállítva", "stopped") }
    var stressRehearsalOnly: String {
        pick("Stresszteszt csak próba módban indítható", "The stress test runs in rehearsal mode only")
    }
    var noGoYet: String { pick("Még nem volt GO", "No GO yet") }

    func memory(now: String, launch: String) -> String {
        pick("\(now) · induláskor \(launch)", "\(now) · at launch \(launch)")
    }

    func goTimings(_ count: Int) -> String {
        pick("GO váltási idő billentyűtől (utolsó \(count))", "GO switch time from key (last \(count))")
    }

    func timings(_ stats: TimingStats) -> String {
        let values = [stats.min, stats.average, stats.max].map { String(format: "%.1f", $0) }
        return pick(
            "min \(values[0]) · átlag \(values[1]) · max \(values[2]) ms (\(stats.count))",
            "min \(values[0]) · avg \(values[1]) · max \(values[2]) ms (\(stats.count))")
    }

    func logTail(_ count: Int) -> String {
        pick("Napló (utolsó \(count) sor)", "Log (last \(count) lines)")
    }

    // --- Last key ---
    func action(_ result: KeyResult) -> String {
        switch result {
        case .nothing: nothing
        case .advanced: pick("Haladó nézet", "Advanced view")
        case .stressStopped: pick("Stresszteszt leállítva", "Stress test stopped")
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
        case .unlockEditing: unlockEditing
        case .lockEditing: lock
        case .requestQuit, .confirmQuitByClick: pick("Kilépés", "Quit")
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
