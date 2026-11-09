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

The output goes to the external display picked on the control screen (else the first external one) and never to the
laptop panel. Files (folder names follow `app.env`):

- Log: `~/Library/Logs/Attacca/YYYY-MM-DD.log`
- State (crash recovery, last show, mode): `~/Library/Application Support/me.blint.attacca/state.json`
- Key map (edit, then relaunch): `~/Library/Application Support/me.blint.attacca/keymap.json`
- Cheat sheet (Advanced view, Ctrl+Opt+D): `~/Library/Application Support/me.blint.attacca/cheatsheet.html`

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
