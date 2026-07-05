# RowPlayFormatting Stress Tests — Design

## Approach

Extend the existing `RowPlayFormattingTests.swift` with additional test methods covering boundary values, invalid inputs, and stress cases for every public method in `RowPlayFormatting`.

## Test Organization

Tests are grouped by method using `// MARK:` sections matching the existing file structure:

1. **time()** — Add boundary second values (1, 59, 60, 61, 3599, 3600) and tenths for a normal value.
2. **pace()** — Add `Double.nan` case.
3. **distance()** — Add boundary metres (1, 999, 1234), very large distance, and metric/imperial consistency checks.
4. **paceToWatts()** — Add very slow pace, `Double.nan` case.
5. **paceToWatts(for:pacePer500m:)** — Add invalid pace returns 0 for each sport.
6. **challengeDistance()** — No new cases needed; existing coverage is complete.

## Formatter Bug Fix Policy

If a test reveals a crash or clearly incorrect behavior in `RowPlayFormatting.swift`, fix only that file. Rules:

- Invalid numeric input must not crash.
- Invalid numeric input returns the existing placeholder (`"--:--"`, `"--"`, or `0`).
- Keep existing public API names.
- Do not change Concept2 pace semantics or BikeErg watts divisor.

## Files Changed

- `Tests/RowPlayCoreTests/RowPlayFormattingTests.swift` — new test methods
- `Sources/RowPlayCore/Support/RowPlayFormatting.swift` — only if a bug is found
- `docs/beta-readiness.md` — update recommended PRs list
- `.kiro/specs/rowplay-formatting-stress-tests/` — this spec
