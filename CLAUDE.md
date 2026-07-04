# CLAUDE.md

@AGENTS.md

`AGENTS.md` is the canonical repository guide for all coding agents.

## Claude-Specific Notes

- **GUI verification**: Always use the staged `.app` bundle (`./script/build_and_run.sh --verify` or `--logs`). Never launch the raw SwiftPM executable directly.
- **Debugging**: Use `./script/build_and_run.sh --debug` to launch under LLDB when you need breakpoint or crash investigation.
- **Telemetry inspection**: Use `./script/build_and_run.sh --telemetry` to stream subsystem-scoped logs.
- **PR workflow**: Run `swift test`, `swift build`, and `git diff --check` before opening a PR. Add `./script/build_and_run.sh --verify` for UI changes.
