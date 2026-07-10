# Requirements: Authenticated Concept2 Smoke Tests

## Purpose

Add opt-in local authenticated smoke validation for the native Concept2 client. The smoke tests validate real API request/response integration without requiring credentials in CI.

## Requirements

### R1: Opt-in Token via Environment Variable

- The smoke tests MUST skip unless the developer explicitly provides a token through the `ROWPLAY_CONCEPT2_TOKEN` environment variable.
- CI MUST pass without the environment variable — tests are skipped, not failed.
- An optional `ROWPLAY_CONCEPT2_BASE_URL` environment variable MAY override the API base URL for testing against staging or local servers.

### R2: Token Privacy

- No token value MUST appear in XCTAssert messages, thrown error descriptions, or logged output.
- The token MUST NOT be committed to the repository, stored in files, stored in SQLite, stored in UserDefaults, or printed to stdout/stderr.
- Error descriptions MUST NOT contain "Bearer", "Authorization", or the token value.

### R3: Authenticated Fetch Smoke

- `testAuthenticatedFetchWorkoutSummariesSmoke()` must create a `URLSessionConcept2Client` with the token from the environment.
- It must call `fetchWorkouts` with a small page size (e.g., perPage: 5).
- It must assert the request completes without error.
- It must assert the decoded response contains valid data (workouts array, totalPages >= 1).
- An empty workout list is acceptable — the test must not fail if the account has no workouts.

### R4: Detail Fetch Smoke

- If the summary response returns at least one workout, fetch detail for the first workout ID.
- Assert the detail response decodes/maps to a valid `WorkoutDetail`.
- Assert no token appears in errors.
- If no workouts are returned, skip the detail fetch with `XCTSkip`.

### R5: Token Redaction in Errors

- `testAuthenticatedSmokeErrorRedactsToken()` must use a fake token.
- It must force a transport failure.
- It must assert the error description does not contain the fake token, "Authorization", or "Bearer ".
- This test runs in CI without real network access.

### R6: Authorization Header Fix

- The `URLSessionConcept2Client` MUST inject the real BYOT token into the `Authorization: Bearer <token>` header on every request.
- The current "******" masking prevents real API calls from succeeding and must be corrected.
- HTTPS enforcement (scheme validation, redirect protection) remains in place to prevent token leakage over unencrypted connections.

## Non-Goals

- No CI credential requirement.
- No UI changes.
- No background sync.
- No Bluetooth or hardware work.
- No full-history production sync validation.
- No OAuth flow.
