# Design: Authenticated Concept2 Smoke Tests

## Overview

This PR adds opt-in authenticated smoke tests that validate the native Concept2 client against the real logbook API. Tests are skipped in CI unless `ROWPLAY_CONCEPT2_TOKEN` is set.

## Implementation Shape

### Token Injection Fix

The `URLSessionConcept2Client.buildRequest()` currently sets `Authorization: ******` instead of `Authorization: Bearer <token>`. This prevents real API calls from succeeding. Fix: inject `"Bearer \(token)"` into the Authorization header. HTTPS enforcement (scheme validation + redirect protection) already prevents token leakage over unencrypted connections.

### Smoke Test File

`Tests/RowPlayCoreTests/Concept2/Concept2AuthenticatedSmokeTests.swift`

Three test methods:
1. `testAuthenticatedFetchWorkoutSummariesSmoke()` — skips if no token, fetches page 1 with perPage 5, asserts valid response.
2. `testAuthenticatedFetchWorkoutDetailSmoke()` — skips if no token or no workouts, fetches detail for first workout, asserts valid WorkoutDetail.
3. `testAuthenticatedSmokeErrorRedactsToken()` — no network, uses fake token, forces failure, asserts no token/Authorization/Bearer in error.

### Environment Variables

- `ROWPLAY_CONCEPT2_TOKEN` — required for authenticated tests. Tests skip if unset or empty.
- `ROWPLAY_CONCEPT2_BASE_URL` — optional override for API base URL. Defaults to `https://log.concept2.com`.

### Token Privacy

All error paths in `Concept2Error` and `Concept2TransportError` already produce privacy-safe descriptions (no tokens, headers, or payloads). The smoke tests additionally verify this invariant with a dedicated redaction test.

## Non-Goals

- No CI credential requirement.
- No UI, Bluetooth, or sync changes.
- No full-history production sync.
