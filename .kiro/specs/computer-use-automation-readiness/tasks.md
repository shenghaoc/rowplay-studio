# Computer Use Automation Readiness — Tasks

## Task 1: Diagnose and remove the incompatible accessibility representation

- [x] Use temporary local probes to identify the failing framework AX container.
- [x] Confirm SwiftUI `GroupBox` is the offending representation.
- [x] Replace workout-tool `GroupBox` instances with `WorkoutToolSection`.
- [x] Remove diagnostic isolation code after confirming the full surface works.

## Task 2: Preserve full-surface semantic access

- [x] Add explicit semantic labels and values for dashboard and workout-detail charts.
- [x] Preserve all replay modes, navigation, and workout-tool controls in the normal UI.
- [x] Avoid duplicate VoiceOver section-title announcements.

## Task 3: Keep automation deterministic without changing the app surface

- [x] Add stable bundle metadata, ad-hoc signing, and strict verification.
- [x] Add `--automation` to the staged launch script.
- [x] Read `ROWPLAY_AUTOMATION` once at launch.
- [x] Force demo data, skip sync, and reduce replay motion in automation mode.

## Task 4: Cache render-facing derived data

- [x] Add a single-pass `WorkoutAnalytics.strokeSummary(for:)` helper.
- [x] Cache summaries in `WorkoutLibrary` when details change.
- [x] Supply the cached summary to `WorkoutDetailView` accessibility labels.

## Task 5: Validate

- [x] `swift test` passes.
- [x] `swift build` passes.
- [x] `git diff --check` passes.
- [x] `./script/build_and_run.sh --verify` launches.
- [x] `./script/build_and_run.sh --automation` launches.
- [x] `codesign --verify --deep --strict dist/RowPlayStudio.app` passes.
- [x] Computer Use traverses the full production accessibility tree and remains running.
