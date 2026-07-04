# Copilot Instructions

Read [`AGENTS.md`](../AGENTS.md) — it is the canonical repository guide for all coding agents.

## Copilot-Specific Notes

- Prefer small, reviewable diffs scoped to one feature or fix.
- Respect the SwiftPM package layout: `RowPlayCore` for pure logic, `RowPlayStudio` for the SwiftUI shell.
- Do not invent app architecture beyond what `docs/roadmap.md` and `.kiro/specs/` define.
- Run `swift test`, `swift build`, and `git diff --check` before proposing changes.
- For UI or bundle changes, also run `./script/build_and_run.sh --verify`.
