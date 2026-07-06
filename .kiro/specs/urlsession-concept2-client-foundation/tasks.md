# URLSession Concept2 Client Foundation — Tasks

## Implementation

- [ ] Create `Sources/RowPlayCore/Concept2/HTTPTransport.swift` — protocol + URLSession implementation
- [ ] Create `Sources/RowPlayCore/Concept2/Concept2Endpoint.swift` — endpoint enum with URL construction
- [ ] Create `Sources/RowPlayCore/Concept2/Concept2Error.swift` — typed errors with redaction
- [ ] Create `Sources/RowPlayCore/Concept2/Concept2Models.swift` — raw API response models
- [ ] Create `Sources/RowPlayCore/Concept2/Concept2Mapper.swift` — raw → domain mapping
- [ ] Create `Sources/RowPlayCore/Concept2/URLSessionConcept2Client.swift` — main client

## Tests

- [ ] Create `Tests/RowPlayCoreTests/Concept2/URLSessionConcept2ClientTests.swift`
  - [ ] testWorkoutSummariesRequestUsesExpectedPath
  - [ ] testAuthorizationHeaderUsesInjectedToken
  - [ ] testAcceptHeaderRequestsJSON
  - [ ] testDecodesWorkoutSummaryResponse
  - [ ] testNon2xxThrowsTypedError
  - [ ] testTransportFailurePropagatesAsConcept2Error
  - [ ] testClientDoesNotPersistToken
- [ ] Create `Tests/RowPlayCoreTests/Concept2/Concept2EndpointTests.swift`
  - [ ] testWorkoutSummariesPath
  - [ ] testWorkoutSummariesPagination
  - [ ] testWorkoutDetailPath
  - [ ] testBaseURLPreserved

## Docs

- [ ] Update `docs/source-map.md`
- [ ] Update `docs/beta-readiness.md`
- [ ] Update `docs/roadmap.md` if needed

## Validation

- [ ] `swift test` passes
- [ ] `swift build` passes
- [ ] `git diff --check` clean
- [ ] No UI, Bluetooth, SQLite schema, or real network changes
