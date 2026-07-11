# TCX Export Tasks

- [x] Add `WorkoutExport.tcx(_ detail: WorkoutDetail) -> String` to `Sources/RowPlayCore/Export/WorkoutExport.swift`.
- [x] Add TCX date formatter (cached `ISO8601DateFormatter` with `.withInternetDateTime`).
- [x] Add `xmlEscape(_:)` helper for XML entity encoding.
- [x] Add `tcxCadence(_:)` helper to round and clamp cadence to 0...255.
- [x] Add stroke filtering, validation, distance clamping, and timestamp deduplication.
- [x] Add "Export TCX" button to `Sources/RowPlayStudio/Views/WorkoutFileActionsView.swift`.
- [x] Create `Tests/RowPlayCoreTests/Export/TCXExportTests.swift` with XMLParser-based validation.
- [x] Update `docs/roadmap.md` Phase 5 status to mark TCX export complete.
- [x] Update `docs/beta-readiness.md` to remove TCX export from Should-Fix.
- [x] Update `docs/source-map.md` with TCX exporter mapping.
- [x] Run `swift test --filter TCXExportTests` and `swift test --filter WorkoutExportTests`.
- [x] Run `swift test` — 720 tests pass, 0 failures.
- [x] Run `swift build` — clean build.
- [x] Run `git diff --check` — no whitespace errors.
- [x] Run `./script/build_and_run.sh --verify` — app launches successfully.
