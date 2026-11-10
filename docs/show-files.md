# Show files

Reference for anything that writes Attacca files by hand or from a script (cutlist tools, other Claude sessions).
The in-app editor writes the same format.

## Rules

- Two file types: `<name>.movie.json` (clips of one piece) and `<name>.concert.json` (the evening: movies, black,
  breaks, logos). The suffix decides the type. Anything else is opened as a movie.
- UTF-8 JSON, no comments. `"format": 1` is required in both.
- Paths are relative to the JSON file's folder (absolute paths work but break when the folder moves).
- Unknown keys are ignored when reading, and dropped the first time the editor saves the file. Keep extra metadata
  (bars, audio notes, source project, approvals) in a separate file, never only in the show file.
- "Open folder" on a clip folder uses `<folder name>.movie.json` inside it when it exists, else builds one from the
  `NN_name.*` video files (MKV, WebM, AVI and similar are listed red, to convert, unless a same-named MP4 exists).
- Check a file without the UI: `build/Attacca.app/Contents/MacOS/Attacca --check <file>`. Exit 0 ok, 1 warnings,
  2 a clip can't play, 3 the file can't be loaded.

## Movie: `<name>.movie.json`

```json
{
  "format": 1,
  "title": "The Greatest Showman",
  "items": [
    { "type": "clip", "file": "00_title.mp4", "number": 0, "title": "Title",
      "planned_end_s": 5.005, "tail_s": 55.013 },
    { "type": "clip", "file": "01_the_greatest_show.mp4", "number": 1, "title": "The Greatest Show",
      "planned_end_s": 75.033, "tail_s": 60.019 },
    { "type": "black" }
  ]
}
```

| Key | Required | Meaning |
|---|---|---|
| `format` | yes | Always `1`. A higher number makes the app say "update the app". |
| `title` | yes | Movie header in the cue list. |
| `items` | no | Cues in play order. Allowed types: `clip`, `black`, `break`, `logo`. No `movie` inside a movie. |
| `colour` | no | `"#RRGGBB"`, kept on save, not shown yet. |

Clip item:

| Key | Required | Meaning |
|---|---|---|
| `type` | yes | `"clip"` |
| `file` | yes | MP4 or MOV (H.264, HEVC, ProRes). MKV, WebM and most AVI don't play. |
| `number` | no | Digit keys 0 to 9 arm the clip with that number. Default: the `NN_` filename prefix. |
| `title` | no | Shown in the list and previews. Default: filename without prefix, `_` to spaces, words capitalised. |
| `planned_end_s` | no | Seconds where the music ends. White marker, big "to planned end" timer. No value means no markers. |
| `tail_s` | no | Safety footage after the planned end, in seconds. Amber marker at `planned_end_s + tail_s`. |
| `colour`, `brief` | no | Kept on save, not shown yet. |

Preflight warns (still plays) when a clip isn't 1920x1080, isn't 23.976 fps, `planned_end_s` is past the end of the
file, or the file length differs from `planned_end_s + tail_s` by more than 1.05 s.

## Concert: `<name>.concert.json`

```json
{
  "format": 1,
  "title": "Spring Gala 2026",
  "logos": ["logos/orchestra.png", { "loop": "logos/event_loop.mp4" }],
  "items": [
    { "type": "black" },
    { "type": "movie", "file": "The Greatest Showman/The Greatest Showman.movie.json" },
    { "type": "break", "minutes": 20, "countdown": true, "text": "Szünet" },
    { "type": "logo", "logo": 1 }
  ]
}
```

| Key | Required | Meaning |
|---|---|---|
| `format`, `title` | yes | As in a movie. |
| `logos` | no | Logo 1 (L key) and logo 2 (Shift+L). Image path, or `{ "loop": "file.mp4" }` for a muted looping video. `""` = no file (shows black). A GIF shows its first frame only: convert it to a looping MP4. |
| `items` | no | Allowed types: `movie`, `black`, `break`, `logo`. No `clip` in a concert: put clips in a movie. |

Other item types:

| Item | Keys |
|---|---|
| `{ "type": "black" }` | none |
| `{ "type": "movie", "file": "x.movie.json" }` | `file` required, must exist |
| `{ "type": "break", "minutes": 20, "countdown": true, "text": "Szünet" }` | `minutes` required; `countdown` default false; `text` optional |
| `{ "type": "logo", "logo": 1 }` | 1-based index into the concert's `logos` |

## Not in the file

Handled by the app, so there is no key for them: hold the last frame at the end of a clip, start muted, key bindings
(`keymap.json`, global), fades inside a clip (bake them into the video), per-clip audio, bar numbers (planned).
