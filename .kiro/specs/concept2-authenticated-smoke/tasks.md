# Tasks: Authenticated Concept2 Smoke Tests

## Implementation Tasks

- [ ] Fix `URLSessionConcept2Client.buildRequest()` to inject real `Authorization: Bearer <token>` header.
- [ ] Update `URLSessionConcept2ClientTests.testAuthorizationHeaderUsesInjectedToken()` to expect `"Bearer <token>"`.
- [ ] Create `Concept2AuthenticatedSmokeTests.swift` with three test methods.
- [ ] Update `docs/beta-readiness.md` with smoke test documentation.
- [ ] Update `docs/source-map.md` with smoke test entry.
- [ ] Run `swift test` without token — all tests pass, smoke tests skipped.
- [ ] Run `swift build` — clean build.
- [ ] Run `git diff --check` — no whitespace errors.
