# URLSession Concept2 Client Foundation — Design

## Architecture

```
Concept2APIClient (existing protocol)
    ↑
URLSessionConcept2Client
    ↓
HTTPTransport (protocol)
    ↑
URLSessionHTTPTransport (wraps URLSession)
```

## Components

### HTTPTransport

Protocol accepting `URLRequest` and returning `(Data, URLResponse)`. This is the injectable seam for tests.

### URLSessionHTTPTransport

Production implementation wrapping `URLSession.shared`. The `URLSession` is injected via initializer for future customization.

### Concept2Endpoint

Enum with cases for each supported API endpoint:
- `.workoutSummaries(page:number:)` → `GET /api/users/me/results`
- `.workoutDetail(id:)` → `GET /api/users/me/results/{id}`
- `.workoutStrokes(id:)` → `GET /api/users/me/results/{id}/strokes`

Constructs the full URL from a base URL, preserving any existing path prefix
on custom hosts such as API gateways or local mock servers.

### Concept2Error

Typed error types covering:
- `.unauthorized` — 401
- `.forbidden` — 403
- `.rateLimited` — 429
- `.httpError(statusCode:)` — other non-2xx
- `.invalidURL(path)` — URL construction failure
- `.decodingFailed` — JSON decode failure
- `Concept2TransportError` — underlying URLSession/transport failure

All descriptions redact sensitive data.

### Concept2Models

Minimal Codable structs matching the Concept2 logbook JSON:
- `Concept2WorkoutSummaryResponse` — envelope with `data` array and `meta.pagination`
- `Concept2WorkoutDetailResponse` — envelope with single `data` object
- `Concept2RawResult` — individual workout fields
- `Concept2RawStroke`, `Concept2RawSplit` — detail sub-models

### Concept2Mapper

Static mapping functions:
- `Concept2RawResult` → `Workout` with `workout_type`-aware interval detection
- Raw strokes/splits → `[Stroke]` / `[Split]` with unit normalization (tenths → seconds, decimetres → metres)
- Bike watt calculation matching the web app's normalized sec/500m formula
- Heart-rate mapping for both integer and `{ average, min, max }` payloads

### URLSessionConcept2Client

- Init: `baseURL`, `token` (String), `transport` (HTTPTransport)
- Conforms to `Concept2APIClient`
- Sets `Authorization: Bearer <token>` and `Accept: application/vnd.c2logbook.v1+json` on every request
- Does not log, persist, or expose the token
- Maps HTTP status codes to typed `Concept2Error` cases
- Fetches `/strokes` for workout details when `stroke_data == true`
- Logs decoding failures and non-fatal stroke-fetch failures through `PrivacySafeLogger`

## Web API Reference

From `src/lib/server/concept2.ts`:

- **Base URL**: `https://log.concept2.com` (configurable)
- **Auth header**: `Authorization: Bearer <token>`
- **Accept header**: `application/vnd.c2logbook.v1+json`
- **List endpoint**: `GET /api/users/me/results?page={page}&number={number}`
  - Response: `{ data: RawResult[], meta?: { pagination?: { total_pages?: number } } }`
- **Detail endpoint**: `GET /api/users/me/results/{id}?include=metadata`
  - Response: `{ data: RawResult, metadata?: RawMetadata }`
- **Strokes endpoint**: `GET /api/users/me/results/{id}/strokes`
  - Response: `{ data: RawStroke[] }`
  - Note: separate request, only when `stroke_data === true`

## Unit Normalization

The API returns:
- `time` in tenths of a second → divide by 10 for seconds
- `stroke.t` in tenths of a second → divide by 10 for seconds
- `stroke.d` in decimetres → divide by 10 for metres
- `stroke.p` pace per 500m (rower/skierg) or per 1000m (bike) → divide by 10, then by 2 for bike

## Test Strategy

- `FakeHTTPTransport`: captures `URLRequest`, returns configurable `Data`/`HTTPURLResponse` or throws.
- `SequenceHTTPTransport`: returns ordered responses for multi-request detail fetches (`detail` then `strokes`).
- No real network, no real tokens, no sleeps.
- Tests verify: path construction, auth header, accept header, JSON decoding, detail stroke-fetch sequencing, non-2xx errors, transport failure propagation, token privacy in errors, and mapper regression behavior.
