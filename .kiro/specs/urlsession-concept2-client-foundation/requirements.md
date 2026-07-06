# URLSession Concept2 Client Foundation

## Purpose

Add a testable Concept2 API client boundary backed by URLSession with BYOT token injection.

## Requirements

1. **Concept2Client protocol conformance**: `URLSessionConcept2Client` conforms to the existing `Concept2APIClient` protocol.
2. **HTTPTransport protocol**: Injectable transport abstraction that wraps `URLSession` for testability.
3. **Token injection**: BYOT token is injected via initializer, not read from storage. The client adds `Authorization: Bearer <token>` to every request.
4. **Endpoint construction**: Deterministic URL building matching the web app's Concept2 API routes, including the per-stroke endpoint and custom base URLs with path prefixes.
5. **Typed errors**: `Concept2Error` covers HTTP, URL-construction, and decoding failures, while `Concept2TransportError` wraps transport-level failures. Error descriptions must not include tokens, headers, or raw payloads.
6. **Response decoding**: Minimal Codable models for the Concept2 logbook API response envelopes and workout summary/detail/stroke payloads, including the `heart_rate` number-or-object union.
7. **Domain mapping**: Map raw API responses to existing `Workout`, `Stroke`, and `Split` domain types, including bike pace normalization and interval detection from `workout_type` when summary payloads omit embedded intervals.
8. **Workout detail completeness**: When a result advertises `stroke_data`, the detail fetch attempts the `/strokes` endpoint and maps the returned stroke stream into `WorkoutDetail`.

## Non-Goals (this PR)

- No full Concept2 sync workflow.
- No token persistence (Keychain, files, UserDefaults, SQLite).
- No SQLite write integration.
- No UI changes.
- No wiring into `WorkoutLibrary`, app scenes, or a user-triggered sync flow.
- No real network calls in tests.
- No retries or rate limiting.
- No background sync.
- No Bluetooth or hardware work.

## Privacy Invariant

The BYOT token must not appear in:
- Error descriptions or `localizedDescription`.
- Debug descriptions.
- Test failure messages.
- Log output.
- Any persistent storage.
