# Attacca

[![Build Status](https://app.bitrise.io/app/ac688969-4ec3-4e8f-9769-5f2a9ae909bc/status.svg?token=ArHnvXQT4N79GP5lrqjzXw&branch=main)](https://app.bitrise.io/app/ac688969-4ec3-4e8f-9769-5f2a9ae909bc)

Silent video player for live orchestras. One Mac, two screens: the laptop is the operator's control screen, the
projector shows only video, black, a logo or the break screen. Keyboard first, boring and predictable.

Status: v0.1 in progress for the first rehearsal (2026-11-13). macOS 14+, Apple Silicon and Intel (universal).

## Build

```sh
make test     # CueCore tests with coverage gate
make run      # build and launch the app
make app      # ad-hoc signed universal .app in build/
make zip      # zipped .app for sharing
make samples  # test clips, logos, a movie and a concert in build/samples (needs ffmpeg or nix)
```

## Run

```sh
build/Attacca.app/Contents/MacOS/Attacca build/samples/samples.concert.json   # a concert, movie or clip folder
build/Attacca.app/Contents/MacOS/Attacca                                     # reopens the last show
```

Check a show without the UI (no windows, writes nothing; JSON report on stdout):

```sh
build/Attacca.app/Contents/MacOS/Attacca --check ~/Movies/Gala/gala.concert.json   # or a .movie.json or a clip folder
make check SHOW=~/Movies/Gala/gala.concert.json                                   # same, needs `make app` first
```

Exit codes: 0 ok, 1 warnings (still plays), 2 a clip can't play, 3 the show itself can't be loaded, 64 bad arguments.

The output goes to the external display picked on the control screen (else the first external one) and never to the
laptop panel. Files (folder names follow `app.env`):

- Log: `~/Library/Logs/Attacca/YYYY-MM-DD.log`
- State (crash recovery, last show, mode): `~/Library/Application Support/me.blint.attacca/state.json`
- Key map (edit, then relaunch): `~/Library/Application Support/me.blint.attacca/keymap.json`
- Cheat sheet (Advanced view, Ctrl+Opt+D): `~/Library/Application Support/me.blint.attacca/cheatsheet.html`

## Clip formats

Plays MP4 and MOV (H.264, HEVC, ProRes). MKV, WebM and most AVI files don't play (preflight marks them red). In
rehearsal mode the preflight panel converts them (Konvertálás / Convert): a new `.mp4` next to the original, the
original is never touched, and the show switches to the new file. Needs ffmpeg from Homebrew or Nix; not while a clip
is running. By hand:

```sh
nix shell nixpkgs#ffmpeg --command ffmpeg -i in.mkv -c copy out.mp4               # H.264 inside: seconds, lossless
nix shell nixpkgs#ffmpeg --command ffmpeg -i in.mkv -c copy -tag:v hvc1 out.mp4   # HEVC inside
nix shell nixpkgs#ffmpeg --command ffmpeg -i in.avi -c:v h264_videotoolbox -b:v 20M -c:a aac out.mp4   # anything else
```

## First open

A downloaded (quarantined) build opens via System Settings > Privacy & Security > Open Anyway, or
`xattr -dr com.apple.quarantine <app>`.

## Docs

- [Design](docs/design.md): what it does and why.
- [Plan](docs/plan.md): v0.1 build order.
- [Development](docs/development.md): rules for working on this repo.
- [Operator checklist](docs/operator-checklist.md): one printable page, Hungarian and English.
- [Rehearsal test script](docs/rehearsal-test.md): what to check on the projector before and during rehearsal.
- [Control window prototype](design/control-window.html): clickable mock of the operator screen with example data.
  GitHub shows it as source only: clone the repo, then open `design/control-window.html` in any browser
  (`open design/control-window.html`). Works offline, no internet or Claude needed.
