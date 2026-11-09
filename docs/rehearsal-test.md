# Rehearsal test script

For the owner and the operator at the first rehearsals. The old two-laptop rig stays on the HDMI switch the whole
time. Note every surprise in the log at the bottom; it drives v0.2.

## Before the orchestra arrives (owner, ~20 min)

1. `make samples app`, copy the show folder to the Mac, run through `docs/operator-checklist.md`.
2. Start with the sample concert: `build/Attacca.app/Contents/MacOS/Attacca build/samples/samples.concert.json`.
3. On the real projector, with the frame counter of the sample clips visible:
   1. GO through every cue. Expect no black frame and no flash between clips (frame counter jumps straight to the
      next clip). `grep switch ~/Library/Logs/Attacca/*.log` shows key-to-switch times.
   2. B, B, L, Shift+L, L during a clip: instant cuts, clip keeps running underneath.
   3. Space, arrows, Home, Opt+Right on the next clip, then GO: starts from the parked point.
   4. Let a clip end: last frame holds. GO to the break: countdown, title holds at 0:00.
   5. Move the cursor towards the projector: it stops at the laptop edge.
   6. Unplug HDMI during a clip: nothing on the laptop panel, red NO PROJECTOR. Replug: picture returns in the same
      state. Write down the projector's refresh rates from the top bar.
   7. `grep "NOT ready" ~/Library/Logs/Attacca/*.log` is empty.
4. Load the real show (`Open folder` on the clip folder, or the concert file). Preflight line is green.

## During rehearsal (operator drives, owner beside)

1. Operator runs the real cues with Enter only; owner watches the projector, not the laptop.
2. Conductor restarts mid-piece: operator arms the nearest clip, parks it (Opt+arrows or the slider under NEXT),
   presses GO when the orchestra reaches that point.
3. Cover drill: B during a clip, then B again: picture returns in sync with the music.
4. Pause drill: B, Space, wait, B, Space: continues from the same frame.
5. Sound drill (rehearsal only): M, M within 3 s turns the soundtrack on; M mutes at once.
6. Recovery drill in a break: `kill -9` the app (owner, terminal), flip the switch to the backup rig, relaunch.
   Expect black on the projector and "Recovered. Was playing ..." on the laptop. Flip back.

## Acceptance (before the first concert)

- Cold start to black output under 5 s.
- 2-hour soak: a long show running, no glitch, memory flat (Advanced view).
- 1000 random GO/black/logo switches from the stress runner with no visible artefact.
- `kill -9` then relaunch returns to black.

## Log

| Time | What happened | What the operator expected | Fix idea |
|---|---|---|---|
| | | | |
