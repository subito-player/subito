# Slots (design, not built)

Status 2026-11-10: agreed with the owner in a mockup (private canvas
https://claude.ai/artifact/9N2KUUhxUk1G16F7m3tyPY). Building as v0.3 for the first rehearsal (2026-11-13), plan in
`plan.md`. Main spec: `design.md`. Choices marked "(call)" were made after the builder check, not by the owner.

## Why

The operator needs more than two logos on hand during a concert: a sponsor card, a thank-you loop, an interval card,
an encore title. Today only Logo 1 and 2 exist (L, Shift+L). Slots give the operator a row of pictures they prepared
before the show, each one press away.

## What a slot is

A logo with a name. It holds one image or one short video that loops (like looping logos). It is always a **cover**:

- Press: the picture fades over the projector in 0.5 s. A running clip keeps running underneath, in step with the
  music. Rehearsal sound is not touched.
- Press again: it fades out, the picture underneath comes back.
- B, L, Shift+L or another slot: swaps the cover (instant between pictures, as Logo 1 to Logo 2 is today).
- GO: clears it and plays NEXT, exactly as with logos.
- A video slot is muted, loops seamlessly and restarts from its first frame each time it is shown.
- Concert mode: slots work. Changing them needs edit mode (rehearsal, or an unlocked concert).
- Pressing an empty slot, or one whose file can't load, changes nothing on the projector; the status line says why.
  The same now holds for L and Shift+L with no logo (they used to cover in black). (call: a stray numpad press must
  never black out the show)

Anti-goals: a slot never replaces the live item (no "GO slots"), never moves NEXT, never plays sound, and the
projector never shows a slot's name.

## Control window

- The button area gets two rows. Row 1: Play, Restart, -30, -5, +5, +30, BLACK, Sound. Row 2, "Logos and slots":
  Logo 1, Logo 2, slots 1 to 6. GO sits left of both rows, spans their height and is about twice as wide as today.
- Each slot button: a small thumbnail, the name, its key, and a tag: DEFAULT (from the default set) or CONCERT (this
  concert's own). An empty slot is a dashed "empty" button. The active cover has the amber ring logos have today.
- Edit mode: clicking a slot selects it and the inspector shows Name, File (image or looping video, Choose...),
  "Saved for" (Every concert = default set / This concert only), "Back to default", the key (read-only, from the
  key map) and "Empty this slot" (press twice). Empty slots show "+ Add". Logo 1 and 2 work the same, without a
  name; the concert inspector's Logo 1/2 pickers go.
- "Saved for" is where the next change goes (call): with a concert open it starts at "This concert only", so a
  change never rewrites the default by accident; "Every concert" must be picked on purpose. With a single movie open
  only "Every concert" exists. A change under "This concert only" creates the concert's own copy; "Back to default"
  drops it; "Empty this slot" writes "empty in this concert" or clears the default, by the same choice.
- In edit mode a click on a logo or slot selects it (call); keys still show and hide covers. BLACK is unchanged.

## Keys

- Numpad 1 to 6 trigger slots 1 to 6; every slot is also clickable. L and Shift+L stay on Logo 1 and 2.
- Top-row digits keep arming clip N. Today the numpad digits arm too; with slots they stop arming (keypad Enter and
  keypad -/+ keep GO and arm previous/next). `KeyInput` must then tell keypad digits from top-row digits (new chord
  names in `keymap.json`, e.g. "Num1").
- The MacBook keyboard has no numpad, so on the laptop alone slots are click-only; a USB numpad adds the keys.
- The show Mac already has a `keymap.json` (written once, with the old defaults). If its bindings equal the v0.2
  default it is rewritten with the new default; a customised file is kept and the status line says slots have no keys
  (call).
- Later, maybe: move arming off the digit keys entirely so slots can take them (owner: "not sure if we wanna use it").

## Default set and concert overrides

- A default set is saved on this Mac (`~/Library/Application Support/<bundle id>/slots.json`, absolute paths):
  Logo 1, Logo 2 and slots 1 to 6.
- A concert file stores only what it changes: `"slots": [null, {"name": "Sponsor 2026", "file": "slots/sponsor.png"},
  null, ""]`, where `null` = use the default, `""` = empty in this concert. Paths relative to the concert as usual.
- The concert's `"logos"` are the Logo 1 and 2 overrides with the same rule: `null` or missing = default, `""` =
  empty here, a path = own. Old concert files load unchanged; a logo they leave out now shows the default logo
  instead of nothing (call: that is what a default set is for).
- Movies have no slots; opening a single movie shows the default set, L and Shift+L included.
- To confirm with the operator at the rehearsal: does "default set plus per-concert changes" match how they prepare a
  concert? (Owner's recommendation.)

## Loading and checks

- Every slot file loads when the show opens (images decoded, videos prerolled), so a press never waits.
- Preflight checks slot files like logos. The Convert button stays clips-only in v0.3 (call); a slot video that can't
  play is red and gets converted by hand (README).
- `--check` reads the default set too.
- Crash recovery: output comes back black as today; an active slot cover is not restored.

## Left to the builder

State machine shape for N covers (generalising `Cover.logo(n)`), how slot thumbnails are made, where `slots.json` is
read and written, file layout of the new code. Tests pin the cover rules above and the default/override merge.
