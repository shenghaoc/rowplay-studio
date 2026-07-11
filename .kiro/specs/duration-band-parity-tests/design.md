# Duration Band Parity Tests — Design

## Overview

This is a test/parity hardening PR. It adds direct unit tests for
`WorkoutAnalytics.durationBand(for:)` using a golden JSON fixture that encodes
the web implementation's verified output. No production behavior is changed.

## Parity source

The web `durationBand` function lives at `src/lib/analytics.ts` (lines 131–161
in the current web repo). It implements:

1. **Standard targets** with ±10% snap windows: 60, 240, 1200, 1800, 3600 s.
2. **Coarse range fallback**: 0–90, 90–360, 360–900, 900–2400, 2400–4800,
   4800+ seconds.
3. **Other fallback**: any value not matching a range (negative, NaN, ∞).

The native implementation at
`Sources/RowPlayCore/Analytics/WorkoutAnalytics.swift` (lines 175–203) uses
identical logic.

## Fixture structure

`Tests/RowPlayCoreTests/Fixtures/duration-band-parity.json` is a JSON array:

```json
[
  {
    "name": "descriptive-test-name",
    "inputSeconds": 1800,
    "expectedKey": "1800",
    "expectedLabel": "30 min",
    "expectedNominalSeconds": 1800
  }
]
```

## Test file structure

`Tests/RowPlayCoreTests/DurationBandParityTests.swift` follows the established
`PerformancePredictorParityTests` pattern:

1. A private `Fixture` struct matching the JSON schema.
2. `setUpWithError` loads fixtures via `ParityFixtureLoader.loadJSON`.
3. `testFixturesLoaded` asserts non-empty.
4. `testDurationBandParity` iterates all fixtures and asserts key, label, and
   nominal match.
5. Direct tests for negative, NaN, and infinity inputs.

## Package.swift

The new fixture is registered as `.copy("Fixtures/duration-band-parity.json")`
in the `RowPlayCoreTests` target resources.

## Non-finite handling

| Input | Expected key | Expected label | Nominal |
|---|---|---|---|
| −1 | `"other"` | `"Other"` | −1 |
| `Double.nan` | `"other"` | `"Other"` | NaN |
| `Double.infinity` | `"other"` | `"Other"` | ∞ |

These are tested with direct assertions (not via fixture) because JSON cannot
represent NaN or Infinity.

## ComparabilityGuard integration

One focused assertion is added to verify that `ComparabilityGuard.areComparable`
consumes the same duration-band key for two time-axis workouts in the same
standard window. This strengthens the indirect coverage without weakening
existing tests.

## Non-goals

- No Bluetooth/CoreBluetooth, TCX export, FIT/TCX/GPX import, UI changes,
  network work, SQLite changes, production analytics refactor, external
  dependencies, performance optimization, or unrelated cleanup.
