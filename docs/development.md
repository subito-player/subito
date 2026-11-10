# Development

Built entirely by Claude agents. Rules adapted from the temporal hub. Spec: `design.md`, plan: `plan.md`.

## Loop

1. One branch per checkpoint in `plan.md` (A to D), branched off `main`, one PR each, base `main`. No stacked PRs;
   state merge order in the PR.
2. Every behaviour change ships with tests and the matching docs update in the same commit. No CHANGELOG; the PR
   describes the change.
3. Before every commit: `make lint test`. App behaviour that needs a screen is checked by hand with
   `docs/rehearsal-test.md`.
4. No test exists just to exist: every test pins a behaviour from `design.md` or a real bug. `make test` has a 90%
   line-coverage gate on `CueCore` as a smoke alarm, not a target; never write a filler test to pass it. If the only way
   to reach 90% is a meaningless test, lower the gate and say why in the PR.
5. Build and test locally (`make run`). CI is Bitrise only (root `bitrise.yml`, no GitHub Actions) and runs only on
   `v*` tags. `bitrise.yml` is also edited by the Workflow Editor, which strips comments: keep it comment-free.
6. Release: bump `VERSION`, merge, tag `vX.Y.Z` on that commit. Release notes come from git history and merged PRs.

## Commits and PRs

- Subject `<area>: <what>`, short, lowercase. Areas: `core`, `app`, `build`, `ci`, `docs`. Body only for a
  non-obvious why.
- No `Co-Authored-By`, no `Claude-Session`, no claude.ai links.
- PR body: 3 to 5 bullets (what, why, merge order), last line `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- Never push to `main` directly, never force-push it. Exceptions so far: the one-time initial commit into the empty
  repo, and the owner-ordered author-email rewrite of 2026-11-10.
- Merge with `gh pr merge --merge --delete-branch --author-email me@blint.me`: GitHub otherwise signs the merge commit
  with the account's primary email.
- After a merge, check the commits are ancestors of `origin/main` (`git merge-base --is-ancestor`).
- Tags and releases: owner only.

## Agents

- Main thread writes a self-contained brief per task (from `plan.md` and `design.md`), dispatches an `implementer`
  (Opus for design-heavy work: state machine, playback, output window; Sonnet for mechanical work: strings, docs,
  build files).
- A reviewer audits each diff; the implementer is resumed with the findings.
- Main thread verifies (`make lint test app`), then commits, pushes the branch and opens the PR.
- Reports carry verification (commands run, results), not relayed agent claims.

## Code

- KISS: simplest thing that works. No abstraction until its second real use.
- Don't reinvent the wheel: standard library, then Apple frameworks, then (only if ~10 lines can't do it) one
  well-known library. Today: no dependencies.
- Comments only for a non-obvious why: one line, present-tense rationale, never history or fix narration.
- App name, command, bundle ID and update repository only in `app.env`; version only in `VERSION`.
- Formatting and lint: `swift format` from the toolchain.
- Every file ends with exactly one newline.
