# Subito v0.1 plan

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
8. **Polish.** `Strings.swift` HU/EN table + toggle, cheat sheet HTML from keymap, Advanced view (Ctrl+Opt+D, log tail, timings, modes, memory, stress runner).
9. **Docs.** `docs/operator-checklist.md` (HU+EN), `docs/rehearsal-test.md`, refresh-rate + first-run notes. Whole-branch review (reviewer agent), fix, `make test && make app`.
   **Checkpoint D: branch + PR (`docs/development.md`).**

Execution: per `docs/development.md`: implementer agent per task (Opus for 3-5, Sonnet for 1, 8, 9), reviewer per diff, main thread verifies, commits, pushes, opens PR.
Estimate: A ~1 h, B ~3 h more, C ~3 h more, D ~2 h more (wall clock, me working). Hardware checks on TV/projector are yours.

## v0.2 (started 2026-11-09 night, owner asleep; one branch + PR per item, review per item)

1. **`--check <show>`**: headless preflight from the command line. JSON report on stdout, exit 0 ok / 1 warnings / 2 blocked / 3 show unreadable / 64 usage; never writes files, no windows. `make check SHOW=...`.
2. **Logo fade**: L / Shift+L cover fades in and out over 0.5 s; BLACK and GO stay instant cuts.
3. **Converter**: preflight panel "Konvertálás" on blocked clips; ffmpeg (Homebrew, Nix, or `nix shell`) remux first, hardware H.264 transcode if needed; new file next to the original, show updated; rehearsal only, never while a clip is live.
4. **Looping logos**: `{ "loop": "file.mp4" }` logos play as a muted seamless loop; concert inspector picks logo 1 and 2 files (image or video).

## v0.3: slots (started 2026-11-10, owner wants it for the 2026-11-13 rehearsal)

Spec: `slots.md` (mockup: private canvas linked there). Goal: a row of logos and slots the operator prepared, each one
press away, as covers like Logo 1 and 2. One branch + PR per task, implementer (Opus) + reviewer per task.

**Architecture:** a slot is a logo number. Pictures 1 and 2 are Logo 1 and 2, pictures 3 to 8 are slots 1 to 6, and
the existing cover path (`Cover.logo(n)`, `PlaybackEngine.setLogos`, logo fade, loop players) shows them unchanged.
New: a default set on the Mac, per-concert overrides, a merged list of 8 pictures fed to the engine, keypad keys,
the two-row button area and the slot inspector.

**Constraints:** CueCore Foundation-only; no new dependencies; HU + EN strings in `Strings.swift`; no em dashes; files
end with one newline; agents never commit or launch the app; `make lint test app` green before every PR.

**Review focus** (each gets a test in its task):
1. The owner's existing `keymap.json` is the old default: after the upgrade slots must have keys; a customised file
   is never overwritten (task 1).
2. Old concert files (`logos` with `""` entries, no `slots`) load and show the same, and a save adds no `slots` key
   when nothing is overridden (task 1).
3. A slot file that is missing or can't play (moved folder, default set path gone) shows black like a missing logo,
   preflight names it, nothing crashes (tasks 1, 2).
4. Locked concert: slot presses work, slot editing is impossible (task 3).
5. A single movie open (no concert): the default set shows; "This concert only" is unavailable (tasks 2, 3).

### Task 1: core (CueCore + KeyInput)

- `Sources/CueCore/Slots.swift`: `pictureCount = 8`; `SlotEntry { name: String, file: String }` (video extension
  mp4/mov/m4v = loop, else image); `SlotOverride { useDefault, empty, own(SlotEntry) }` coded as `null` / `""` /
  object; `SlotSet { format, logos: [Logo?] (2), slots: [SlotEntry?] (6) }` = the default set, absolute paths;
  `PictureSource { defaultSet, concert }`; `Picture { name, file: LogoFile, source }`;
  `Pictures.merge(defaults: SlotSet, concert: Concert?, concertURL: URL?) -> [Picture?]` (always 8; logos named
  "Logo 1"/"Logo 2").
- `Models.swift`: `Concert.logos` becomes `[Logo?]` (null = default, `""` = empty here, path = own); `Concert.slots:
  [SlotOverride]` (missing = []; encoded only when non-empty; trailing defaults trimmed in both arrays).
- `ShowDocument.swift`: `Edit.setPicture(Int /* 1...8 */, SlotOverride)` replaces `setLogoFile` (paths stored relative
  as logos are today); logo cue items keep pointing at 1 or 2 only (no slot as a live item: owner said no GO slots).
- `KeyMap.swift`: key names `Num0`...`Num9`; action `slot:N` (1...6) = `.toggleCover(.logo(N + 2))`; default map adds
  `Num1`...`Num6`; loading a file whose bindings equal the v0.2 default rewrites it with the new default.
- `Sources/CueApp/KeyInput.swift`: keypad keyCodes 82-92 give `Num0`...`Num9` (keypad digits stop arming).
- Tests: merge matrix (default/empty/own for logos and slots, old `logos` files), concert round trip, `setPicture`,
  keys (`Num1` -> logo 3, `1` -> arm 1), old-default keymap upgrade vs customised file kept, slot cover fades in from
  nothing and cuts between pictures (`ShowState.fadesCover`).

### Task 2: engine, default set, preflight (CueApp)

- Default set store: load/save `~/Library/Application Support/<bundle id>/slots.json` (atomic; missing = empty set;
  broken = empty set + red status line, never overwritten until the owner edits).
- `AppModel`: `pictures: [Picture?]` = `Pictures.merge(...)`, recomputed on open, document edit and default-set edit;
  engine, preflight and `--check` (`Check.swift`) use it instead of `document.logos`.
- Preflight: every picture checked like logos today, findings named by slot name.
- A cover press (key or click) on a picture that is empty or failed to load is refused before it reaches the state
  machine: nothing on the projector changes, status line notice. Applies to L / Shift+L too.

### Task 3: control window (CueApp UI)

- `Transport.swift` `ButtonRow`: GO left of two rows, spanning both, about twice today's width. Row 1: Play, Restart,
  -30, -5, +5, +30, BLACK, Sound. Row 2 "Logók és slotok" / "Logos and slots": 8 buttons (thumbnail from the decoded
  image, "LOOP" label for videos; name; key; DEFAULT / CONCERT tag; dashed "empty"); amber ring on the active cover.
  Click = the same command as the key.
- Edit mode: clicking a logo or slot selects it (`selectedPicture: Int?`) instead of toggling it; keys still
  toggle. Inspector: Name (slots only), File (Choose..., image or video), "Saved for" = where the next change goes
  (starts at This concert only when a concert is open; only Every concert with a movie open), Back to default,
  Empty (press twice). The concert inspector's Logo 1/2 pickers go (the slot row replaces them).
- Strings HU + EN, cheat sheet lists slot keys.

### Task 4: `?` key list (CueApp UI, parallel with task 1)

- Top bar `?` button toggles a non-modal panel over the cue list with the active key map in the UI language (the
  cheat sheet's content, in-app). Keys keep driving the show while it is open; works in both modes.

### Task 5: docs and release

- `design.md` (keys table: numpad slots, keypad digits no longer arm; control window; editor), `show-files.md`
  (`slots`, `logos` null), `rehearsal-test.md` (slot TV checks), README. VERSION 0.3.0; owner TV check, then tag.

## MCP server (started 2026-11-11, branch `mcp`, spec: `design.md` "MCP server")

1. **Core** (`CueCore`): JSON-RPC/MCP stdio handler (initialize with version negotiation, ping, tools/list,
   tools/call, notifications ignored, protocol errors) and the four tools over `ShowLoader`/`ShowDocument`; check and
   "open in the running app" injected as closures. Tests pin each `design.md` rule.
2. **App** (`CueApp`): `--mcp` in the launch parser and `main.swift`; stdin line loop; check = `Check`'s report;
   open-show lookup from `state.json` + running Subito processes; `make app` bundles `docs/show-files.md`.
3. **Docs**: README "Use with Claude" (Desktop config, `claude mcp add`), usage text.
4. **Trial**: headless Claude Code session with `--mcp-config` builds a movie and a concert from a sample folder;
   `--check` and the app open the result. Owner tries Claude Desktop. Merge if usable.

## Claude setup buttons (started 2026-11-11, branch `claude-connect`)

1. [x] **Core** (`CueCore/ClaudeSetup.swift`): `codeCommand` (single-quoted path), `manifest` (`.mcpb` manifest 0.3,
   binary server), `pack` (`ditto` zip with the files at the root). Tests: quoting survives `/bin/sh`, manifest
   fields, zip root listing.
2. [x] **App** (`CueApp/ClaudeConnect.swift`): icon PNG from the running app, pack to the temp folder, open with
   Claude Desktop, notices (not installed, pack or open failed), Copy to the pasteboard. Install and Copy refuse a
   dmg-mounted or translocated app; the copied command removes the old entry first (last setup wins).
3. [x] **Advanced view**: "Claude" section after Updates (Install button with notice, command with Copy), install
   rehearsal only; Strings HU + EN.
4. [x] **Docs**: README "Use with Claude", `design.md` MCP section.
5. [x] **Trial** (owner, 2026-11-11): Install from the build's Advanced view, Claude Desktop accepted the extension
   and ran `check_show` on a real concert (ok, 11 cues). The Copy command was not tried.
