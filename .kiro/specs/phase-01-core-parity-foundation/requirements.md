# Phase 1 Requirements: Core Parity Foundation

## R1: DateTime Helpers

The native app must parse Concept2 logbook timestamps (`YYYY-MM-DD HH:MM:SS`, UTC wall clock) and perform calendar arithmetic without depending on the JS Temporal API.

- **R1.1** `logbookEpochMillis` parses `YYYY-MM-DD HH:MM:SS` to epoch milliseconds (UTC).
- **R1.2** `dayKeyFromDate` converts a `Date` to a `YYYY-MM-DD` string in UTC.
- **R1.3** `dayKeyAddingDays` adds N calendar days to a `YYYY-MM-DD` key.
- **R1.4** `daysBetween` returns the non-negative calendar day count between two `YYYY-MM-DD` keys.
- **R1.5** `dayOfWeek` returns 0=Sun..6=Sat from a `YYYY-MM-DD` key.
- **R1.6** `todayKeyUTC` returns today as `YYYY-MM-DD` in UTC.
- **R1.7** All functions are pure and deterministic (except `todayKeyUTC` which is clock-dependent but trivially testable).

## R2: Performance Predictor

The native app must replicate Paul's Law distance predictions from the web app.

- **R2.1** `predictTimes` returns a dictionary mapping standard Concept2 distances to predicted seconds from a known (distance, time) pair.
- **R2.2** `buildPredictionTable` compares predictions against personal bests and classifies each row as `beaten`, `behind`, or `untried`.
- **R2.3** Output matches the web app's `performancePredictor.ts` for identical inputs.

## R3: Privacy Redaction

- **R3.1** `isPubliclyShareable` returns `true` only when the Concept2 privacy string is exactly `"everyone"` (case-insensitive, trimmed).
- **R3.2** All other values (`nil`, `"private"`, `"logged_in"`, `"partners"`, garbage) return `false`.

## R4: Pace Input Parsing

- **R4.1** `parsePaceInput` parses `M:SS` or bare numeric strings to positive seconds, or nil for invalid input.
- **R4.2** `formatPaceInput` formats positive seconds as canonical `M:SS`.
- **R4.3** Round-trip: `formatPaceInput(parsePaceInput(s))` produces canonical `M:SS` for valid inputs.

## R5: Personal Bests

- **R5.1** `distancePBs` returns the fastest workout per standard distance (500, 1000, 2000, 5000, 6000, 10000, 21097).
- **R5.2** `pbWorkoutIds` returns the set of workout IDs that are PBs at any standard distance.
- **R5.3** Distance matching uses ±2% tolerance.
- **R5.4** Output matches the web app's `analytics.ts` `distancePBs` and `workoutQuery.ts` `pbWorkoutIds` for identical inputs.

## R6: Parity Fixture Infrastructure

- **R6.1** A `ParityFixture` struct captures inputs and expected outputs for cross-platform comparison.
- **R6.2** Fixture JSON files are loadable from the test bundle.
- **R6.3** Golden parity tests assert native output matches web-verified values for the performance predictor.

## R7: Test Coverage

- **R7.1** Every ported helper has dedicated XCTest coverage.
- **R7.2** Edge cases are covered: empty inputs, zero values, invalid strings, boundary distances.
- **R7.3** `swift test` passes.
- **R7.4** `swift build` passes.
