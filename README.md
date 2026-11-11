<h1>
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="design/logo/subito-lockup-light.svg">
    <img src="design/logo/subito-lockup-dark.svg" height="72" alt="Subito">
  </picture>
</h1>

[![Build Status](https://app.bitrise.io/app/ac688969-4ec3-4e8f-9769-5f2a9ae909bc/status.svg?token=ArHnvXQT4N79GP5lrqjzXw&branch=main)](https://app.bitrise.io/app/ac688969-4ec3-4e8f-9769-5f2a9ae909bc)

Silent video player for live orchestras. One Mac, two screens: the laptop is the operator's control screen, the
projector shows only video, black, a logo or the break screen. Keyboard first, boring and predictable.

Status: v0.4.1 (LIVE shows covers), first rehearsal 2026-11-13. macOS 14+, Apple Silicon only.

Renamed from Attacca on 2026-11-10: releases up to v0.3.0 carry the old name. The first launch under the new name
copies the old settings (key map, default set, language, output display).

## Build

```sh
make test     # CueCore tests with coverage gate
make run      # build and launch the app
make app      # ad-hoc signed Apple Silicon .app in build/
make zip      # zipped .app for sharing
make dmg      # disk image: open it, drag Subito to Applications
make samples  # test clips, logos, a movie and a concert in build/samples (needs ffmpeg or nix)
```

## Run

```sh
build/Subito.app/Contents/MacOS/Subito build/samples/samples.concert.json   # a concert, movie or clip folder
build/Subito.app/Contents/MacOS/Subito                                     # reopens the last show
```

Check a show and this Mac's default set without the UI (no windows, writes nothing; JSON report on stdout):

```sh
build/Subito.app/Contents/MacOS/Subito --check ~/Movies/Gala/gala.concert.json   # or a .movie.json or a clip folder
make check SHOW=~/Movies/Gala/gala.concert.json                                   # same, needs `make app` first
```

Exit codes: 0 ok, 1 warnings (still plays), 2 a clip can't play, 3 the show itself can't be loaded, 64 bad arguments.

The output goes to the external display picked on the control screen (else the first external one) and never to the
laptop panel. Files (folder names follow `app.env`):

- Log: `~/Library/Logs/Subito/YYYY-MM-DD.log`
- State (crash recovery, last show, mode): `~/Library/Application Support/me.blint.subito/state.json`
- Key map (edit, then relaunch): `~/Library/Application Support/me.blint.subito/keymap.json`
- Default set (Logo 1, Logo 2, slots 1 to 6): `~/Library/Application Support/me.blint.subito/slots.json`
- Cheat sheet (Advanced view, Ctrl+Opt+D): `~/Library/Application Support/me.blint.subito/cheatsheet.html`

## Use with Claude

`Subito --mcp` is a local MCP server for show preparation: Claude reads, writes and checks movie and concert files,
for example after cutting the operator clips in another tool. Show files only: it never starts or controls the app or
the projector, never writes the key map, the default set or the state file, and opens no network port. Install and
open the app once first (see First open).

Set up from the Advanced view (Ctrl+Opt+D), Claude section, in rehearsal mode:

- Claude Desktop: click "Install in Claude Desktop" (Telepítés a Claude Desktopba), then Install in the dialog Claude
  Desktop opens.
- Claude Code: click Copy (Másolás), paste the command in a terminal.

Both point at the app you clicked in, and the last setup wins: Claude Desktop replaces the extension of the same name,
and the copied command removes the old `subito` entry first. Do it from the app in `/Applications`: from a mounted dmg
or a quarantined download the buttons ask you to move the app first. Remove any hand-added `subito` entry from
`claude_desktop_config.json` before using Install, otherwise Desktop runs two. By hand instead:

Claude Desktop: add this to `~/Library/Application Support/Claude/claude_desktop_config.json`, then restart Claude
Desktop:

```json
{
  "mcpServers": {
    "subito": {
      "command": "/Applications/Subito.app/Contents/MacOS/Subito",
      "args": ["--mcp"]
    }
  }
}
```

Claude Code:

```sh
claude mcp add --scope user subito -- /Applications/Subito.app/Contents/MacOS/Subito --mcp
```

For a build from source, use the absolute path of `build/Subito.app/Contents/MacOS/Subito` instead.

What Claude can do with it:

- `show_file_format`: read the [show file format](docs/show-files.md) before writing.
- `read_show`: a movie, a concert or a clip folder as Subito reads it (a folder without a movie file: the movie
  Subito would make from its clips, not saved).
- `write_show`: write a whole movie or concert file. It gets the same checks Subito runs when it opens a show, and an
  invalid show is never written. Paths inside the show that are absolute or start with `~` are stored relative when
  they are inside the show's folder, else absolute. A file it replaces goes to the macOS Trash first, so a wrong
  write can be undone from Finder. Answers with the check report of the written file.
- `check_show`: the `--check` report.

What it cannot do: play, arm or switch anything, change the key map or the default set, or take a relative path as a
tool argument (tool paths are absolute or start with `~`).

Write guard: `write_show` refuses a file that a running Subito has open (the open show, or a movie of the open
concert), because the app's next save would overwrite it. Close the show in Subito (open another show or quit), let
Claude write, then open it again. Started from a bare build binary (no app bundle) it cannot tell, so it refuses
every write: always point Claude at `Subito.app/Contents/MacOS/Subito`. Each tool call is one line on stderr, which
Claude Desktop keeps in its MCP logs (`~/Library/Logs/Claude/mcp*.log`).

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

Logos: PNG or JPG, or a short MP4 that loops. An animated GIF shows only its first frame; convert it to MP4 and pick
that instead:

```sh
nix shell nixpkgs#ffmpeg --command ffmpeg -i logo.gif -pix_fmt yuv420p -vf "scale=trunc(iw/2)*2:trunc(ih/2)*2" -c:v libx264 -crf 18 -an logo.mp4
```

## First open

From a release: download the `.dmg`, open it and drag Subito onto Applications (or unzip the `.zip`). A downloaded
(quarantined) build opens via System Settings > Privacy & Security > Open Anyway, or
`xattr -dr com.apple.quarantine <app>`. In rehearsal mode the app tells you about newer releases (a badge in the top
bar that opens the download); it never installs anything and never checks in concert mode.

## Docs

- [Design](docs/design.md): what it does and why.
- [Show files](docs/show-files.md): movie and concert JSON format, for scripts that generate them.
- [Plan](docs/plan.md): v0.1 build order.
- [Development](docs/development.md): rules for working on this repo.
- [Operator checklist](docs/operator-checklist.md): one printable page, Hungarian and English.
- [Rehearsal test script](docs/rehearsal-test.md): what to check on the projector before and during rehearsal.
- [Control window prototype](design/control-window.html): clickable mock of the operator screen with example data.
  GitHub shows it as source only: clone the repo, then open `design/control-window.html` in any browser
  (`open design/control-window.html`). Works offline, no internet or Claude needed.

## License

Copyright (C) 2026 Bálint Réthelyi. Subito is free software: you can redistribute it and/or modify it under the
terms of the GNU General Public License v3.0, see [LICENSE](LICENSE). The logo's letter is Playfair Display (SIL Open
Font License 1.1), see [design/logo](design/logo/README.md).
