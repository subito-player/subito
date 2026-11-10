# Subito v0.1 design

Silent video player for live orchestras. Draft 2026-11-09. Target: rehearsal Fri 2026-11-13 (or that weekend).

## Why

Orchestra plays live, film projected behind it. Today: 2 laptops, HDMI switch, prebaked screens (logos, black).
VLC + remote was tried: it dropped out of fullscreen when switching between files from different sources, and the
conductor lost trust. Subito runs on one Mac (laptop screen = control, projector = output), is keyboard driven,
boring and predictable.

**Anti-goals** (failure even if it technically works): anything on the projector except video, black, logo or break
screen (no cursor, UI, dialog, desktop, error text, OSD); output leaving its display or its fullscreen state; a modal
dialog swallowing Enter or Space mid-show; the operator needing to know it is a Mac.

**Non-goals:** video editing, audio mixing, lighting, network sync, effects, two machines, Windows (later, separate decision).

## People and setup

- Operator: non-technical, Hungarian speaker. Owner sits beside them at first rehearsals, not at concerts.
- Show Mac: this one (Apple Silicon, macOS 27.2). Min target macOS 14 so a backup Mac can run it.
- Projector: HDMI, refresh modes unknown. Old 2-laptop rig stays on the same HDMI switch as backup.
- Clips: own exports (1920x1080 H.264 23.976, planned part + 60 s tail + 1 s fade, watermark, rehearsal audio), and
  later clips from other creators in any size, fps or codec. First rehearsal: own export only.

## Content model

Two file types, plain JSON, paths relative to the file. Operator builds both in the app; a spreadsheet script may
also generate movie files.

```json
// showman.movie.json
{ "format": 1, "title": "The Greatest Showman", "colour": "#7a4aff",
  "items": [
    { "type": "clip", "number": 0, "file": "clips/00_title.mp4", "title": "Title",
      "planned_end_s": 45, "tail_s": 0, "colour": "#444", "brief": "Pause on title, wait for conductor" },
    { "type": "clip", "number": 1, "file": "clips/01_the_greatest_show.mp4", "title": "The Greatest Show",
      "planned_end_s": 212.5, "tail_s": 60 },
    { "type": "black" } ] }

// gala-2026.concert.json
{ "format": 1, "title": "Spring Gala 2026", "logos": ["logos/orchestra.png", "logos/event.png"],
  "items": [
    { "type": "black" },
    { "type": "movie", "file": "showman.movie.json" },
    { "type": "break", "minutes": 20, "countdown": true, "text": "Szünet" },
    { "type": "logo", "logo": 1 } ] }
```

- Clip fields except `type` and `file` are optional. `number` defaults to the `NN_` filename prefix, `title` to the
  rest of the filename ("the_greatest_show" -> "The Greatest Show"). No `planned_end_s` = no markers.
- Concert refers to movies by file, so fixing a movie fixes every concert using it.
- Logo entries are an image path or `{ "loop": "file.mp4" }`: a muted video that loops seamlessly and restarts from
  frame 0 each time it is shown. A named logo is `{ "name": ..., "file": ... }` like a slot; the name replaces
  "Logo 1" on the control window, never on the projector. `null` or left out = the default set's logo, `""` = no logo in this concert
  (`slots.md`). A logo cue is 1 or 2: one with no file, or any other number, shows black and preflight warns. Logo 1
  and 2 are picked like slots, in the picture inspector (editor below).
- "Open folder" builds a movie from `NN_name.mp4` (also `.mov`, `.m4v`) files and saves `<folder>.movie.json` next to
  them. MKV, WebM, AVI and other ffmpeg formats are listed too (red in preflight, ready to convert) unless an MP4 or
  MOV with the same name is already there.

## Behaviour

**Output = live item + optional cover.** Live item: black, logo, break, or clip (playing, paused, or ended holding its
last frame; no loop, no stop screen). Cover: none, black, logo 1, logo 2, slot 1 to 6.
- B / L / Shift+L / keypad 1 to 6 put a cover over the live item. The clip under it keeps its state: playing keeps
  running hidden (in step with the music), paused stays on its frame. Space, seek and Home still act on the covered
  clip; LIVE preview names the cover and the clip's state, e.g. "COVERED · Logo 1 · running".
- Same key again removes the cover (no separate uncover key). Another cover key swaps the cover.
- A logo or slot that is empty, or whose file did not load, never comes on: the press changes nothing on the
  projector and the status line says why ("Slot 3 is empty"). Taking a cover off always works; B is never refused.
- Black, then continue later from the same frame: B, Space (pause hidden), ... B (frame back), Space (play).
- Cover is picture only: rehearsal audio of a covered running clip keeps playing.
- GO replaces the live item and clears any cover. GO onto a black, logo or break item ends the clip (planned).

**ARM / GO:** armed item loads paused on frame 0 and shows in the NEXT preview. Armed clip can be parked anywhere
before GO (Opt+arrows or drag its own scrub bar under NEXT); GO starts it from there. Rehearsal flow: arm nearest
clip, park it at a musical point, wait until the orchestra gets there, GO. GO auto-arms the next item in the
flattened list. The projector only changes on a key press. GO is refused (status line says why) until the armed
clip has a frame ready.

**Break screen:** big text plus optional mm:ss countdown from GO, over black (or logo 1 if set). At 0:00 the countdown
disappears and the screen holds. Rendered content, not UI.

**Keys** (`keymap.json`, numpad/footswitch need no code; keypad digits are keys of their own, `Num0` to `Num9`):

| Key | Action | Key | Action |
|---|---|---|---|
| Enter, keypad Enter | GO | B | black cover on/off (instant cut, always) |
| Space | play/pause live clip (also covered) | L / Shift+L | logo 1 / 2 cover on/off (fades 0.5 s in and out; logo 1 <-> 2, BLACK and GO cut) |
| Left/Right | seek live 5 s | Shift+Left/Right | seek live 30 s |
| Opt+Left/Right | park armed 5 s | Opt+Shift+Left/Right | park armed 30 s |
| Up/Down, keypad -/+ | arm previous/next item | 0 to 9 (top row) | arm clip with that number in current movie; keypad digits never arm |
| Home (Fn+Left) | restart live clip | M | mute instantly; sound on needs a 2nd press within 3 s (rehearsal only) |
| Esc | nothing | Cmd+Q | quit (press twice; concert: press twice + click) |
| Ctrl+Opt+D | toggle Advanced view | Keypad 1 to 6 | slot 1 to 6 cover on/off, like a logo (`slots.md`) |

A stray Shift or Option still reaches the other keys; digits arm only with no modifier held.
Last key and its action are shown in the control window.

**No modal dialogs during a show.** Every confirmation is "press again within 3 s", shown as a banner, so Enter or
Space can never land in an alert.

**Modes** (toggle at top, press twice to switch; switching never touches the output):

| | Rehearsal | Concert |
|---|---|---|
| Editing | on | locked; "Unlock editing" + confirm, orange banner, live item can't be moved or deleted, Lock button relocks |
| Plays | any movie, concert or clip folder (Open) | the concert list |
| Audio | muted at launch, M toggles, loud badge naming the device ("AUDIO ON → HDMI") for the whole room | forced mute, M disabled |
| Output view | Fullscreen, Window or Off (debugging; click twice; every launch starts Fullscreen) | always Fullscreen |
| Banner | none | big CONCERT |

The mode survives every launch: a clean launch restores the saved mode too, so concert stays concert.

**Editor (v0.1, minimal):** new movie, new concert (opens in edit mode); add clips (file picker or drag in), black,
break, logo, movie (to concert: + Movie, or drag in a `.movie.json` or clip folder); drag reorder; delete (press
twice); rename; brief, planned end, tail, break minutes and countdown fields. Dragging Finder files onto the list
starts editing (rehearsal, or unlocked concert); an empty show says what to do. Autosave, atomic write. Later: undo,
templates, duplicate.
Picture inspector (edit mode, click a logo or slot; it replaces the row selection, and the status line says a click
there selects): "Saved for" first = where the next change goes: This concert only (where it starts, on every
selection, with a concert open) or Every concert (the default set; the only choice with a single movie open), then
Name, File (Choose...: an image, or an MP4, MOV or M4V that loops), its key (read-only), Back to default
(the concert's own picture or ""), Empty (press twice). A new name or file keeps the other field of the picture shown.
Every concert includes the open one: a change or Empty there also drops this concert's own setting, so it shows at
once.
While an editor text field is being edited, keys go to the field (banner says so); Enter or Esc ends typing, and
from then on keys drive the show again.

**Control window (layout A, always dark):** top bar (mode toggle, concert title, Open, projector/power/audio/Hz
status dots, last key, HU/EN, `?` for the key list); left 30% two-level list (movie headers, items, LIVE red, ARMED
amber); right LIVE and NEXT previews side by side, the clip's brief (2 lines) under each title (NEXT has its own small scrub bar for
parking), progress bar with white planned-end and amber tail-end markers, big "to planned end" time,
smaller "to clip end"; button area: a big GO on the left spanning two rows, row 1 Play, Restart, -30, -5, +5, +30,
BLACK, Sound, row 2 "Logos and slots": Logo 1, Logo 2, slots 1 to 6, each with a thumbnail ("LOOP" for a video), its
name, key and a DEFAULT or CONCERT tag, dashed "empty" when unset, a red dot when its file can't load, the amber ring
while it is the cover; a click does what its key does (in edit mode it selects); status line at bottom (plain
language, no codec names). Window fills the laptop screen so there is nothing else to click. If the app loses focus: big red "keys not
reaching the app, click here" banner.

**Advanced view (Ctrl+Opt+D, for the owner):** log tail, key-to-switch timings, projector modes, memory use (now and
at launch), stress runner (random GO/BLACK/LOGO/arm, rehearsal only, any key stops it), cheat sheet, key map and log
folder buttons. Per-clip file details are in the preflight panel and the log.

**Key map file:** `~/Library/Application Support/<bundle id>/keymap.json`, written with the defaults on first launch,
read at launch. A file still holding the v0.2 default keys is rewritten with the current default (it adds the slot
keys); any other file is never rewritten, and slots it gives no key are reported. A broken file falls back to the
default keys with a red status line naming the problem. Button labels and the cheat sheet follow the active map.
Cheat sheet: one printable A4 page in the current UI language.

**Preflight** (launch and on load, results on control only): files exist; playable by AVFoundation (red if not, plain
message); size, fps, codec, duration vs `planned_end_s + tail_s` (yellow if off by > 1 s plus one frame or not
1920x1080 23.976, still plays); logos and slots load; logo cues are 1 or 2; projector present and not mirrored (a
projector mirroring the laptop is red, never an output); power adapter; current Hz and available rates; "Displays
have separate Spaces" value; current sound output device (yellow if HDMI; app never changes it). Manual ticks:
Focus/Do Not Disturb on, automatic updates off, black desktop wallpaper on every display, old rig ready. Status line
shows the summary ("All good", "2 warnings", red "1 clip cannot play"); clicking it toggles the list (non-modal
panel, ticks not saved). Blocked cues get a red dot in the cue list. System checks re-run on display, sound device and
power changes.

**Projector unplugged:** hide output window at the start of any display reconfiguration (macOS reports it for every
display, so we can't tell which one is going away), never let macOS move it to the laptop. Cost: a brief desktop
flash on the projector during any reconfiguration, hence the black wallpaper. Red status on control. Playback
continues. Control screen: the built-in panel, or the main display when there is none (lid closed, Mac mini), unless
that main display is the picked output, then the first other display. Output display: the one picked on the control
screen (vendor, model, serial) when present, else the first other display; never the control screen; one display
only means no output. Attaching never changes the saved pick. Re-show output in the current state when it returns.

**Parked GO:** a clip armed at a position (parked, or recovered) is ready for GO only after the seek to that position
has finished, so GO can never flash frame 0. A seek that never finishes is retried once, then the clip is reported
ready with an amber warning, so GO is never refused forever.

**Quitting:** only through the confirmed press-twice quit. Dock Quit asks like Cmd+Q; logout and restart for updates
are refused while the app runs.

**Crash recovery:** state file written every second (open concert, mode, live item, position, cover). Relaunch: output
black, same concert and mode, the previously live clip armed at its last position, status "Recovered. Was playing 03
at 2:14." A confirmed quit marks the state clean, so the next launch opens the last show; a file given at launch
wins and recovers only if it is the same show. If two recovered launches in a row crash before a GO, the next launch
opens the show and mode without arming ("Recovery skipped after repeated crashes"). Only one instance may run. While
the app is dead the projector shows the desktop: checklist says "switch to backup rig, relaunch".

**Languages:** Hungarian default, English toggle in app, takes effect immediately. Own two-column string table
(Apple localisation can't switch language in-app without relaunch). Logs English.

## Architecture

- SwiftPM package, no Xcode project, no dependencies. Targets: `CueCore` (Foundation only: models, file loading,
  flattening, state machine, key map, `Player` protocol), `CueApp` (AppKit, SwiftUI for control window, AVFoundation),
  `CueCoreTests` (state machine, file parsing, key map). Module names neutral so a rename touches one file.
- Name, command, bundle ID, tagline live only in `app.env` (plain `KEY=value`, included by the Makefile). Code reads
  name and ID from `Bundle.main`.
- Build via `Makefile`: `make test`, `make app` (release build, assemble .app, Info.plist from `app.env`, sign),
  `make run`, `make zip`, `make clean`. Signing: `SIGN_ID ?= -` (ad-hoc now; Developer ID + notarisation later is a
  variable change plus one target).
- Testing and day-to-day builds run locally (`make test`, `make run`). CI kept minimal: `bitrise.yml` in repo, macOS
  Apple Silicon stack, one `release` workflow triggered by `v*` tags only: `make test`, `make app`, `make zip`, upload
  zip as artifact, machine `g2.mac.medium`. Builds on `main` merges: add a push trigger in the Workflow Editor.
- Repo: `https://github.com/Blintmester/Subito.git`.
- First open of a CI-built (downloaded, quarantined) ad-hoc app: System Settings > Privacy & Security > Open Anyway,
  or `xattr -dr com.apple.quarantine <app>`. Locally built apps open directly.
- Output window: borderless NSWindow at `CGShieldingWindowLevel`, frame = output screen frame, collection behaviour
  `canJoinAllSpaces, stationary, ignoresCycle, fullScreenNone`, never key, black background layer. Presentation
  options while up: hide Dock and menu bar, disable process switching and hide. Force Quit stays enabled. Cursor:
  warped back to the control screen if it crosses onto the output screen. Native fullscreen rejected: own Space,
  animated, exits on Esc or gestures.
- Playback: two AVPlayers swapping live/armed roles, each with one layer on the output and one in a control preview.
  `automaticallyWaitsToMinimizeStalling = false`, `actionAtItemEnd = .pause`, armed player prerolled. GO = one
  CATransaction with actions disabled: show armed layer, hide others, then play. Clips scale with
  `resizeAspect` on black, so any size or aspect works. Logo and break are CALayers on the output.
- Sleep: `ProcessInfo.beginActivity(.idleDisplaySleepDisabled, .idleSystemSleepDisabled)` for the app's lifetime.
- Display: `CGDisplayRegisterReconfigurationCallback` (begin flag -> hide output), `CGDisplayCopyAllDisplayModes`
  for Hz, `CGDisplayIsInMirrorSet`. Power: `IOPSGetProvidingPowerSourceType`.
- Icon: `design/AppIcon.icon` (Icon Composer; default and dark appearance), compiled by `actool` in `make app`; logo
  files in `design/logo/`.
- Logs: `~/Library/Logs/<name>/YYYY-MM-DD.log`, plain lines, keep 14 days. State: `~/Library/Application Support/<bundle id>/`.
- Refresh rate guidance (doc): prefer 23.976 > 47.95 > 71.93 > 24 > 48 > 72 > 60 Hz on the projector. App never
  changes display modes itself.
- Port note (2026-11-10): `CueCore` (~3,200 lines + tests) is Foundation-only and ports; `CueApp` (~6,300 lines:
  AppKit, SwiftUI, AVFoundation, CoreGraphics displays) does not. If a Windows version is needed: one app for Windows
  (and Linux later) in Qt or Rust + Slint with libmpv, `CueCore` ported with its tests as the spec, the Mac app kept
  as is. First a 1-day spike on a real projector: two mpv players, GO with no black frame, unplug/replug.

## v0.1 build order (cut from the bottom if Thursday comes)

1. Output window, two-player ARM/GO, BLACK, LOGO, keys, mute, sleep prevention, single instance, black on relaunch.
2. Movie/concert files, flattened list, auto-arm, break screen, "Open folder".
3. Preflight, status line, display unplug/replug, crash recovery state.
4. Editor, rehearsal/concert modes, emergency unlock.
5. Languages, cheat sheet (HTML from keymap, HU+EN), operator checklist, Advanced view, stress runner.

Deliverables with code: `docs/operator-checklist.md` (HU+EN, one page), generated cheat sheet, `docs/rehearsal-test.md`
(manual test script), first-run note for unsigned builds.

**v0.2 (built):** `--check` headless preflight; logo fade; converter (ffmpeg from Homebrew/Nix, remux only for
H.264/HEVC, else hardware H.264 transcode; rehearsal only, never while a clip is running; new file next to the
original); looping logos.

**Later:** slots (`slots.md`, designed, build after the first rehearsal; maybe later: move arming off the digit
keys), editor extras, bar numbers mapped to timestamps (park armed clip by bar), phone status mirror / rehearsal
remote, rehearsal timer, per-clip notes, Windows.

## To verify on hardware before Friday

Verified 2026-11-09 (owner desk, macOS 27.2, output on the main external display): the shielding-level black window
stays black through Cmd+Tab, window drags, Mission Control, Spaces switches, a fullscreen app on another display,
notification banners, volume/brightness HUD, Spotlight and Esc.

Still open: behaviour with "separate Spaces" off; projector Hz list; HDMI unplug/replug with output live; GO switch
time and no black frame on TV and projector.
