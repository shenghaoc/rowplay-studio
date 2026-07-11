# TCX Export Tasks

- [x] Add `WorkoutExport.tcx(_ detail: WorkoutDetail) -> String` to `Sources/RowPlayCore/Export/WorkoutExport.swift`.
- [x] Add per-export TCX date formatters for activity timestamps and fractional-second trackpoints.
- [x] Add inline cadence validation that rounds and clamps to the TCX range `0...254` before integer conversion.
- [x] Add stroke filtering, validation, distance clamping, and timestamp deduplication.
- [x] Add "Export TCX" button to `Sources/RowPlayStudio/Views/WorkoutFileActionsView.swift`.
- [x] Create `Tests/RowPlayCoreTests/Export/TCXExportTests.swift` with XMLParser-based validation.
- [x] Update `docs/roadmap.md` Phase 5 status to mark TCX export complete.
- [x] Update `docs/beta-readiness.md` to remove TCX export from Should-Fix.
- [x] Update `docs/source-map.md` with TCX exporter mapping.
- [x] Run `swift test --filter TCXExportTests` and `swift test --filter WorkoutExportTests`.
- [x] Run `swift test` — 729 core tests pass (2 skipped), 48 app tests pass, 0 failures.
- [x] Run `swift build` — clean build.
- [x] Run `git diff --check` — no whitespace errors.
- [x] Run `./script/build_and_run.sh --verify` — app launches successfully.
