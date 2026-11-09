# Attacca

[![Build Status](https://app.bitrise.io/app/ac688969-4ec3-4e8f-9769-5f2a9ae909bc/status.svg?token=ArHnvXQT4N79GP5lrqjzXw&branch=main)](https://app.bitrise.io/app/ac688969-4ec3-4e8f-9769-5f2a9ae909bc)

Silent video player for live orchestras. One Mac, two screens: the laptop is the operator's control screen, the
projector shows only video, black, a logo or the break screen. Keyboard first, boring and predictable.

Status: v0.1 in progress for the first rehearsal (2026-11-13). macOS 14+, Apple Silicon.

## Build

```sh
make test   # CueCore tests with coverage gate
make run    # build and launch the app
make app    # ad-hoc signed .app in build/
make zip    # zipped .app for sharing
```

A downloaded (quarantined) build opens via System Settings > Privacy & Security > Open Anyway, or
`xattr -dr com.apple.quarantine <app>`.

## Docs

- [Design](docs/design.md): what it does and why.
- [Plan](docs/plan.md): v0.1 build order.
- [Development](docs/development.md): rules for working on this repo.
- [Control window prototype](design/control-window.html): clickable mock of the operator screen with example data.
  Works offline: open `design/control-window.html` in any browser (`open design/control-window.html`), no internet
  or Claude needed. First online version: https://claude.ai/artifact/ADwb3zZzJ4PxD96FJFYx2e (private).
