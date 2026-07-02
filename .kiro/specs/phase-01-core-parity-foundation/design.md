# Phase 1 Design: Core Parity Foundation

## Goal

Port a focused set of pure, testable core helpers from the web app (`rowplay`) into `RowPlayCore`, establishing the parity fixture strategy that will validate native-vs-web correctness for all future phases.

## Scope

This PR ports three helper modules and introduces the parity fixture infrastructure:

### 1. DateTime Helpers (`RowPlayCore/Support/RowPlayDateTime.swift`)

Port the subset of `src/lib/datetime.ts` that does not depend on the Temporal API or DOM:

- `logbookEpochMillis(_:)` — parse Concept2 `YYYY-MM-DD HH:MM:SS` as UTC wall time → epoch ms.
- `dayKeyFromDate(_:)` — `Date` → `YYYY-MM-DD` string in UTC.
- `dayKeyAddingDays(_:to:)` — add calendar days to a `YYYY-MM-DD` key.
- `daysBetween(_:_:)` — calendar day count between two `YYYY-MM-DD` keys.
- `dayOfWeek(_:)` — 0=Sun..6=Sat from a day key.
- `todayKeyUTC()` — today as `YYYY-MM-DD` in UTC.

Swift's `Calendar` and `DateComponents` replace the JS Temporal API. All functions are pure, deterministic, and testable.

### 2. Performance Predictor (`RowPlayCore/Analytics/PerformancePredictor.swift`)

Direct port of `src/lib/performancePredictor.ts`:

- `PAUL_EXPONENT` constant (1.06).
- `PREDICTOR_DISTANCES` — standard Concept2 race distances.
- `predictTimes(knownDistance:knownSeconds:)` — Paul's Law map.
- `buildPredictionTable(knownDistance:knownSeconds:personalBests:)` — prediction rows with beaten/behind/untried status.

Pure math, no dependencies.

### 3. Pace Input (`RowPlayCore/Support/PaceInput.swift`)

Port of `src/lib/paceInput.ts`:

- `parsePaceInput(_:)` — parse `M:SS` or bare seconds to `TimeInterval?`.
- `formatPaceInput(_:)` — format seconds as `M:SS` string.

### 4. Personal Bests (`RowPlayCore/Analytics/PersonalBests.swift`)

Port of PB detection from `src/lib/analytics.ts` and `src/lib/workoutQuery.ts`:

- `PersonalBest` struct with distance, sport, time, date.
- `distancePBs(workouts:)` — fastest workout per standard distance.
- `pbWorkoutIds(workouts:sport:)` — set of PB workout IDs with ±2% distance tolerance.

### 5. Privacy Redaction (`RowPlayCore/Support/PrivacyRedaction.swift`)

Direct port of `src/lib/privacy.ts`:

- `isPubliclyShareable(privacy:)` — true only when Concept2 privacy is exactly `"everyone"`.

### 6. Parity Fixture Strategy (`Tests/RowPlayCoreTests/Fixtures/`)

- `ParityFixture.swift` — a `Codable` struct that captures inputs + expected outputs for a single parity check.
- `ParityFixtureLoader.swift` — loads `.json` fixture files from the test bundle.
- `PerformancePredictorParityTests.swift` — golden tests that assert native output matches web-verified values.

The fixture JSON files are checked into the repo so both web and native can be compared without hand-inspecting charts.

## Non-Goals

- No UI changes.
- No networking, Keychain, SQLite, or Cloudflare work.
- No replay rendering or Bluetooth.
- No workout query/filtering (depends on more module infrastructure; Phase 2).

## File Layout

```
Sources/RowPlayCore/
  Support/
    RowPlayDateTime.swift      (new)
    PaceInput.swift            (new)
    PrivacyRedaction.swift     (new)
  Analytics/
    PerformancePredictor.swift (new)
    PersonalBests.swift        (new)
Tests/RowPlayCoreTests/
  RowPlayDateTimeTests.swift         (new)
  PaceInputTests.swift               (new)
  PerformancePredictorTests.swift    (new)
  PrivacyRedactionTests.swift        (new)
  PersonalBestsTests.swift           (new)
  Fixtures/
    ParityFixture.swift              (new)
    ParityFixtureLoader.swift        (new)
    performance-predictor-parity.json (new)
    PerformancePredictorParityTests.swift (new)
```
