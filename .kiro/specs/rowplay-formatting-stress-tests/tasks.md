# RowPlayFormatting Stress Tests — Tasks

- [x] Add stress/boundary tests for `RowPlayFormatting.time(_:tenths:)` (1s, 59s, 60s, 61s, 3599s, 3600s, tenths for normal)
- [x] Add `Double.nan` test for `RowPlayFormatting.pace(_:)`
- [x] Add boundary tests for `RowPlayFormatting.distance(_:unit:)` (1m, 999m, 1234m, very large, imperial 1609.344m)
- [x] Add stress tests for `RowPlayFormatting.paceToWatts(_:)` (very slow pace, NaN)
- [x] Add invalid-pace test for `RowPlayFormatting.paceToWatts(for:pacePer500m:)` (all sports return 0)
- [x] Fix any formatter bugs exposed by new tests (if needed)
- [x] Update `docs/beta-readiness.md` to remove RowPlayFormatting stress test follow-up
- [x] Validate: `swift test`, `swift build`, `git diff --check`
