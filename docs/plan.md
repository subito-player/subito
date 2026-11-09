# Attacca v0.1 plan

Spec: `docs/design.md`. Swift tools 6.0, macOS 14 min, no deps. `CueCore` Swift 6 mode, `CueApp` Swift 5 mode (AVFoundation/AppKit Sendable noise, speed).

1. **Scaffold.** `app.env`, `VERSION` (0.1.0), `Makefile` (lint/test with 90% CueCore coverage gate/app/run/zip/clean, `SIGN_ID ?= -`), `Package.swift` (CueCore, CueApp, CueCoreTests), `bitrise.yml` (`v*` tag workflow, main trigger commented). App opens black output window + empty control window. Check: `make run`.
2. **CueCore files.** `Models.swift` (Movie, Concert, Item enum clip/black/break/logo/movie, Codable per design JSON), `ShowLoader.swift` (load/save atomic, `movie(fromFolder:)`, `flatten(concert) -> [Cue]`). Tests: design examples parse; `01_the_greatest_show.mp4` -> 1 / "The Greatest Show"; relative paths; flatten order; missing movie file -> error.
3. **CueCore logic.** `ShowState.swift`: `mutating func handle(_: Command) -> [Effect]`, live + cover + armed(at:) + mode + mute. `KeyMap.swift`: `keymap.json` -> `Command`. `Player.swift` protocol (load slot at time, show base, set cover, play/pause/seek, mute). Tests: GO auto-arms next; GO refused if armed not ready; B on/B off; L then B swaps; GO clears cover; GO to black item ends clip; covered clip keeps play state; digits arm within current movie; Up/Down cross movies; park armed; concert mode ignores M; keypad Enter -> GO.
   **Checkpoint A: branch + PR (`docs/development.md`).**
4. **Output + playback.** `OutputWindow.swift` (shielding level, collection behaviour, never key), `PlaybackEngine.swift` (2 AVPlayers, 2 layers each, CATransaction swap, logo/break/cover layers), `DisplayWatcher.swift` (reconfig callback hides before move, re-attach by vendor/model/serial), cursor warp, presentation options, `beginActivity`, single instance. Check: TV, GO/B/L by keyboard, no flash.
5. **Control window, layout A.** SwiftUI: top bar (incl. output display picker, saved by vendor/model/serial), 2-level list, LIVE/NEXT previews (+ park scrub), progress with markers, button row, last key, status line, focus-lost banner, press-twice banner. Keys -> ShowState -> engine. Break countdown.
   **Checkpoint B (rehearsal minimum): branch + PR (`docs/development.md`).**
6. **Safety.** `Preflight.swift` (AVURLAsset checks, display, mirror, power, Hz, Spaces, sound device), `Log.swift`, `Recovery.swift` (state every 1 s, relaunch black + armed at position).
7. **Editor + modes.** Add/delete/reorder/rename, black/break/logo/movie items, clip fields, autosave; rehearsal/concert toggle, emergency unlock, live item protected, concert mute.
   **Checkpoint C: branch + PR (`docs/development.md`).**
8. **Polish.** `Strings.swift` HU/EN table + toggle, cheat sheet HTML from keymap, Advanced view (Cmd+Opt+D, log tail, timings, modes, memory, stress runner).
9. **Docs.** `docs/operator-checklist.md` (HU+EN), `docs/rehearsal-test.md`, refresh-rate + first-run notes. Whole-branch review (reviewer agent), fix, `make test && make app`.
   **Checkpoint D: branch + PR (`docs/development.md`).**

Execution: per `docs/development.md`: implementer agent per task (Opus for 3-5, Sonnet for 1, 8, 9), reviewer per diff, main thread verifies, commits, pushes, opens PR.
Estimate: A ~1 h, B ~3 h more, C ~3 h more, D ~2 h more (wall clock, me working). Hardware checks on TV/projector are yours.
