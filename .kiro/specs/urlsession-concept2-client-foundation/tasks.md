# URLSession Concept2 Client Foundation — Tasks

## Implementation

- [x] Create `Sources/RowPlayCore/Concept2/HTTPTransport.swift` — protocol + URLSession implementation
- [x] Create `Sources/RowPlayCore/Concept2/Concept2Endpoint.swift` — endpoint enum with URL construction, custom base-path preservation, and strokes endpoint support
- [x] Create `Sources/RowPlayCore/Concept2/Concept2Error.swift` — typed errors with redaction and transport wrapper
- [x] Create `Sources/RowPlayCore/Concept2/Concept2Models.swift` — raw API response models for summaries, details, and strokes
- [x] Create `Sources/RowPlayCore/Concept2/Concept2Mapper.swift` — raw → domain mapping, workout-type interval detection, and bike watt normalization
- [x] Create `Sources/RowPlayCore/Concept2/URLSessionConcept2Client.swift` — main client with detail + optional strokes fetch

## Tests

- [x] Create `Tests/RowPlayCoreTests/Concept2/URLSessionConcept2ClientTests.swift`
  - [x] testWorkoutSummariesRequestUsesExpectedPath
  - [x] testAuthorizationHeaderUsesInjectedToken
  - [x] testAcceptHeaderRequestsJSON
  - [x] testDecodesWorkoutSummaryResponse
  - [x] testDecodesWorkoutDetailResponse
  - [x] testWorkoutDetailRequestUsesExpectedPath
  - [x] testNon2xxThrowsTypedError
  - [x] testTransportFailurePropagatesAsConcept2Error
  - [x] testClientDoesNotPersistToken
- [x] Create `Tests/RowPlayCoreTests/Concept2/Concept2EndpointTests.swift`
  - [x] testWorkoutSummariesPath
  - [x] testWorkoutSummariesPagination
  - [x] testWorkoutDetailPath
  - [x] testWorkoutDetailIncludesMetadataParam
  - [x] testBaseURLPreserved
  - [x] testBaseURLWithPathPrefixIsPreserved
- [x] Create `Tests/RowPlayCoreTests/Concept2/Concept2MapperTests.swift`
  - [x] workout summary defaults and heart-rate union mapping
  - [x] bike stroke pace normalization and interval offset accumulation
  - [x] split rest detection and nil cadence preservation
  - [x] bike watt regression coverage

## Docs

- [x] Update `docs/source-map.md`
- [x] Update `docs/beta-readiness.md`
- [x] Update `docs/roadmap.md` if needed
- [x] Keep this Kiro spec aligned with the final code and PR scope

## Validation

- [x] `swift test` passes
- [x] `swift build` passes
- [x] `git diff --check` clean
- [x] No UI, Bluetooth, SQLite schema, or real network changes
