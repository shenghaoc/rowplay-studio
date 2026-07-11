# Duration Band Parity Tests — Requirements

## Introduction

`WorkoutAnalytics.durationBand(for:)` is a pure helper that buckets workout
durations into standard or coarse-range bands for comparability. It is
currently tested only *indirectly* through `ComparabilityGuardTests` (which
consumes its key output). Direct parity tests against the web implementation
(`src/lib/analytics.ts`) ensure native and web bucketing remains identical at
every boundary.

This is a **test/parity hardening** PR. It must not change production behavior
unless a verified mismatch with the current web implementation is discovered.

## Requirements

### Requirement 1 — Parity fixture

**User story:** As a developer, I want a golden JSON fixture that encodes the
web `durationBand` output for representative inputs, so I can verify native
output matches web output at every boundary without hand-inspecting code.

#### Acceptance criteria

1. THE fixture SHALL be a JSON array at
   `Tests/RowPlayCoreTests/Fixtures/duration-band-parity.json`.
2. Each record SHALL contain: `name` (string), `inputSeconds` (number),
   `expectedKey` (string), `expectedLabel` (string), `expectedNominalSeconds`
   (number).
3. Expected values SHALL be copied from the current web `durationBand`
   implementation. No new bucketing behavior SHALL be invented.
4. The fixture SHALL be registered as a `.copy` resource in `Package.swift`.

### Requirement 2 — Standard target coverage

**User story:** As a developer, I want the five standard duration targets
tested at their exact values and ±10% window boundaries, so I know the snap
window is inclusive.

#### Acceptance criteria

1. THE fixture SHALL include the exact standard durations: 60, 240, 1200,
   1800, and 3600 seconds.
2. THE fixture SHALL include each standard's lower boundary (standard × 0.9)
   and upper boundary (standard × 1.1).
3. THE fixture SHALL include values immediately outside each standard window
   (lower − 1, upper + 1) that fall back to coarse bands.

### Requirement 3 — Coarse range coverage

**User story:** As a developer, I want the coarse-range fallback tested at
every range boundary, so the bucketing logic is fully exercised.

#### Acceptance criteria

1. THE fixture SHALL include the range boundaries: 0, 90, 360, 900, 2400,
   and 4800 seconds.
2. Each boundary value SHALL map to the correct coarse-range key.

### Requirement 4 — Web example coverage

**User story:** As a developer, I want the specific web test examples
(1750→"1800", 600→"r360", 90→"r90", 30→"r0" with nominal 45) verified in
native, so I know the implementations agree on real-world inputs.

#### Acceptance criteria

1. THE fixture SHALL include the four web examples from
   `comparabilityGuard.test.ts`: 1750, 600, 90, and 30 seconds.
2. Each SHALL map to the expected key and nominal from the web implementation.

### Requirement 5 — Non-finite value handling

**User story:** As a developer, I want negative, NaN, and infinity inputs
tested, so degenerate inputs produce predictable output.

#### Acceptance criteria

1. THE test file SHALL include direct (non-fixture) tests for negative values,
   `Double.nan`, and `Double.infinity`.
2. Each test SHALL assert the current behavior: key `"other"`, label `"Other"`,
   and the input-preserving nominal where comparison is meaningful.

### Requirement 6 — Label parity

**User story:** As a developer, I want labels verified character-for-character,
including en-dash characters in range labels, so formatting is identical.

#### Acceptance criteria

1. Every assertion SHALL compare the full label string, including en-dash
   (U+2013) characters.
2. The fixture SHALL NOT use ASCII hyphens where the web uses en-dashes.

### Requirement 7 — Assertion messages

**User story:** As a developer, I want every assertion to include the fixture
name or input value, so test failures immediately identify the exact boundary.

#### Acceptance criteria

1. Every `XCTAssert*` call SHALL include a failure message identifying the
   fixture name or input value.

### Requirement 8 — No production changes

**User story:** As a developer, I want this PR to add tests only, so
production behavior is unchanged.

#### Acceptance criteria

1. If native and web behavior already match, `Sources/RowPlayCore` SHALL NOT
   be edited.
2. If a mismatch is found, implementation SHALL stop before changing production
   code and report the mismatch.
3. `ComparabilityGuardTests` SHALL NOT be weakened. A focused assertion may be
   added only if needed to prove it consumes the same duration-band key.
