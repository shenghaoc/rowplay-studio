# Duration Band Parity Tests — Tasks

Implementation plan. Each task is committed and pushed as one unit.
Requirement references point at `requirements.md`.

- [x] **1. Parity fixture** — `Tests/RowPlayCoreTests/Fixtures/duration-band-parity.json`
  - Create JSON fixture with standard targets, ±10% boundary values,
    out-of-window values, coarse range boundaries, and web examples.
  - _Requirements: 1.1–1.3, 2.1–2.3, 3.1, 4.1–4.2, 6.1_

- [x] **2. Package.swift resource registration**
  - Add `.copy("Fixtures/duration-band-parity.json")` to the
    `RowPlayCoreTests` target resources.
  - _Requirements: 1.4_

- [x] **3. DurationBandParityTests** — `Tests/RowPlayCoreTests/DurationBandParityTests.swift`
  - Fixture-driven parity test asserting key, label, and nominal for every
    record. Direct tests for negative, NaN, and infinity. Assertion messages
    include fixture name or input value.
  - _Requirements: 5.1–5.2, 7.1_

- [x] **4. ComparabilityGuard focused assertion**
  - Verify `areComparable` consumes duration-band key for two time-axis
    workouts in the same standard window. Do not weaken existing tests.
  - _Requirements: 8.3_

- [x] **5. Documentation updates**
  - Remove "WorkoutAnalytics.durationBand has no direct tests" from
    `docs/beta-readiness.md`.
  - Update `docs/source-map.md` to mention the native parity fixture and
    direct tests.
  - _Requirements: 8.1_

- [x] **6. Validation**
  - `swift test --filter DurationBandParityTests` ✓
  - `swift test --filter WorkoutAnalyticsTests` ✓
  - `swift test --filter ComparabilityGuardTests` ✓
  - `swift test` ✓ (677 tests, 0 failures)
  - `swift build` ✓
  - `git diff --check` ✓
  - _Requirements: all_

- [x] **7. Publish**
  - Commit, push, open draft PR with summary, parity sources, boundary
    coverage, validation commands, and non-goals.
  - _Requirements: all_
