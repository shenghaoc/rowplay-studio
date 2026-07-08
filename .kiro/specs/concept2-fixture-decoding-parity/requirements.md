# Concept2 Fixture Decoding Parity — Requirements

## Purpose

Validate native Concept2 decoding/mapping against sanitized golden fixtures from the web repo, before real API smoke testing.

## Scope

- This PR validates native Concept2 decoding/mapping against sanitized fixtures.
- This PR does **not** call the real Concept2 API.
- This PR does **not** use real user tokens.
- This PR may fix decoder or mapping bugs exposed by fixtures.
- This PR does **not** add UI or new sync behavior.

## Requirements

1. Copy sanitized Concept2 golden fixtures from the web repo (`rowplay/tests/fixtures/golden/`) into the native test bundle.
2. Add a `Concept2FixtureLoader` helper to load JSON fixtures from `Bundle.module`.
3. Add `Concept2FixtureDecodingTests` covering:
   - Rower steady workout decoding and mapping
   - Rower interval workout decoding and mapping (cumulative t/d offset)
   - SkiErg workout decoding and mapping
   - BikeErg workout decoding and mapping (pace halving, watts divisor)
   - Stroke monotonicity across all fixtures with strokes
   - Fixture secret scanning (no tokens, credentials, or PII)
4. Assert exact fixture-derived parity values where available (id, sport, distance, time, pace, stroke count, split count, first/last stroke t/d).
5. Fix decoder/mapping bugs exposed by fixture coverage.
6. Update `docs/source-map.md` and `docs/beta-readiness.md`.

## Non-Goals

- No real Concept2 API calls or network code.
- No real tokens or credentials.
- No UI changes.
- No background sync.
- No Bluetooth or hardware work.
- No SQLite schema changes.
