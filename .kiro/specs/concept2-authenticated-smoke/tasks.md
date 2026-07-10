# Tasks: Authenticated Concept2 Smoke Tests

## Implementation Tasks

- [x] Verify `URLSessionConcept2Client.buildRequest()` injects the real `Authorization: Bearer <token>` header and that its focused unit test covers the header.
- [x] Create `Concept2AuthenticatedSmokeTests.swift` with authenticated summary/detail smoke coverage, secure base-URL override validation, and redaction coverage.
- [x] Reject non-HTTPS `ROWPLAY_CONCEPT2_BASE_URL` overrides before an authenticated request is built.
- [x] Update `docs/beta-readiness.md` with smoke test documentation.
- [x] Update `docs/source-map.md` with smoke test entry.
- [x] Run `swift test` without token — all tests pass, smoke tests skipped.
- [x] Run `swift build` — clean build.
- [x] Run `git diff --check` — no whitespace errors.
- [ ] Run authenticated smoke tests with a developer-provided token (optional local verification; not required in CI).
