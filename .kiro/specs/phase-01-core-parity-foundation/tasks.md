# Phase 01 Core Parity Foundation Tasks

- [x] Port `RowPlayDateTime.swift` with logbook parsing and calendar arithmetic.
- [x] Port `PaceInput.swift` with pace string parsing and formatting.
- [x] Port `PersonalBests.swift` with distance PB detection.
- [x] Port `PerformancePredictor.swift` with Paul's Law predictions.
- [x] Port `PrivacyRedaction.swift` with share-link guard.
- [x] Create `ParityFixture.swift` and `ParityFixtureLoader.swift` for golden test infrastructure.
- [x] Create `performance-predictor-parity.json` golden fixture with web-verified values.
- [x] Add `RowPlayDateTimeTests.swift` covering all datetime helpers and edge cases.
- [x] Add `PaceInputTests.swift` covering parsing, formatting, and round-trips.
- [x] Add `PersonalBestsTests.swift` covering PB detection and distance tolerance.
- [x] Add `PerformancePredictorTests.swift` covering predictions, table building, and edge cases.
- [x] Add `PrivacyRedactionTests.swift` covering all privacy levels.
- [x] Add `PerformancePredictorParityTests.swift` golden parity tests.
- [x] Update `docs/source-map.md` with new Phase 1 mappings.
- [x] Update `docs/roadmap.md` Phase 1 exit criteria status.
- [x] Run `swift test` - all tests pass.
- [x] Run `swift build` - clean build.
- [x] Run `git diff --check` - no whitespace errors.
