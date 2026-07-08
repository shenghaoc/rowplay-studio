# Concept2 Fixture Decoding Parity — Design

## Overview

This PR adds golden fixture resources from the web repo and tests that the native `Concept2Models` + `Concept2Mapper` decode and map them identically to the web app's `concept2.ts`.

## Fixture Source

Fixtures originate from `rowplay/tests/fixtures/golden/`. Each fixture contains:

- `rawResult`: An API-shaped workout result (matches `GET /api/users/me/results/{id}`)
- `rawStrokes`: Per-stroke data (matches `GET /api/users/me/results/{id}/strokes`)
- `expected`: Hand-verified expected domain values

Fixtures are sanitized: no real user IDs, names, emails, tokens, or device serial numbers. See `REDACTION.md`.

## Fixture Inventory

| Fixture | Sport | Type | Key Behaviour |
|---------|-------|------|---------------|
| `rower-steady.fixture.json` | rower | steady | paceDiv=1, splits present |
| `rower-interval.fixture.json` | rower | interval | t/d reset per rep, cumulative offset |
| `ski-steady.fixture.json` | skierg | steady | paceDiv=1 (same as rower) |
| `bike-steady.fixture.json` | bike | steady | paceDiv=2 halves per-1000m pace, watts/8 |

## Test Strategy

1. **Decode rawResult** → `Concept2RawResult` via `JSONDecoder`
2. **Map to Workout** → `Concept2Mapper.mapWorkout(_:)`
3. **Decode rawStrokes** → `[Concept2RawStroke]`
4. **Map to Strokes** → `Concept2Mapper.mapStrokes(_:sport:)`
5. **Map to Splits** → `Concept2Mapper.mapSplits(_:)`
6. **Assert parity** against `expected.*` values from the fixture

## Parity Assertions

For each fixture, assert:
- `workout.id` == fixture `rawResult.id`
- `workout.sport` == expected sport
- `workout.distance` == expected distance
- `workout.time` ≈ expected time
- `workout.pace` ≈ expected pace
- First/last mapped stroke `t` and `d` match expected
- Split count, time, distance, pace match expected

## Decoder/Mapping Fix Scope

Fixes limited to:
- `Sources/RowPlayCore/Concept2/Concept2Models.swift`
- `Sources/RowPlayCore/Concept2/Concept2Mapper.swift`
- `Sources/RowPlayCore/Models/*` (only if fixture exposes a domain model bug)
- `Sources/RowPlayCore/Support/RowPlayFormatting.swift` (only for watts/pace math)

No unrelated code changes.
