# Reconcile RowPlay Studio With rowplay PR #166 — Requirements

## Context

rowplay PR #166 (`refactor: remove all KV and D1 dependencies`) merged to
`main` on 2026-07-10. It removes Cloudflare KV session storage and D1 workout
caching from the web app. The web app is now stateless for server-managed
storage: authenticated workout summaries and details are fetched live from the
Concept2 Logbook API per request, identity and optional OAuth tokens are sealed
in the AES-GCM httpOnly `rp_session` cookie, and a personal Concept2 token is
sealed separately in the httpOnly `rp_tok` cookie. Server-persistence-era
features (leaderboards, public shares, coaching annotations, server-persisted
HR imports, manual tags, sync/backfill, comparison, and account-data deletion)
have been removed or retired.

RowPlay Studio's roadmap, source-map, beta-readiness notes, and steering docs
were written against the pre-PR-166 web architecture. They must be reconciled
so that:

1. No documentation tells agents to port KV/D1 behavior from the web app.
2. Removed web features are not presented as current parity targets.
3. Native SQLite cache is correctly described as a native-local/offline
   capability, not as web D1 parity.
4. Future native sync work is framed as native-local cache behavior, not as
   D1/KV parity chasing.

## Requirements

### 1. Web architecture baseline

1. `docs/roadmap.md` SHALL include a "Web Architecture Baseline" section
   stating that the web app is stateless with no KV/D1 workout cache as of
   PR #166.
2. The section SHALL clarify that native SQLite cache is a RowPlay
   Studio-specific capability, not web parity.
3. The section SHALL state that removed web features should not be presented
   as current parity targets.

### 2. Roadmap phase language

1. Every phase in `docs/roadmap.md` SHALL be reviewed for stale references to
   KV, D1, Cloudflare, sync/backfill, leaderboards, public shares,
   annotations, manual tags, HR import, compare, or account deletion.
2. Stale claims SHALL be either removed, clarified as native-only/future, or
   marked as retired from web parity.
3. Native goals SHALL NOT be removed blindly. Edits SHALL be surgical.

### 3. Source map

1. `docs/source-map.md` SHALL mark web files removed by PR #166 as retired.
2. Any claim that native code maps to web D1/KV storage as current parity
   SHALL be corrected.
3. Native SQLite cache entries SHALL be labeled as "Native-only local cache,
   not web D1 parity."
4. A reference to the web `.kiro/specs/remove-kv-d1/` spec SHALL be added as
   the current web source of truth.

### 4. Beta readiness

1. `docs/beta-readiness.md` SHALL include a "rowplay PR #166 Impact" section.
2. The section SHALL note web KV/D1 removal, removed storage-era features,
   native SQLite as native-local only, and that future sync must not chase
   removed web D1/KV architecture.

### 5. Steering docs

1. `.kiro/steering/structure.md` SHALL NOT tell agents to port KV/D1
   behavior.
2. `.kiro/steering/tech.md` SHALL NOT list removed web features as current
   parity requirements without noting they are retired/future/native-only.
3. `AGENTS.md` SHALL accurately reflect the current state of the
   `WorkoutCache` production implementation.

### 6. Spec

1. A new `.kiro/specs/reconcile-rowplay-166-architecture/` spec SHALL be
   created with requirements, design, and tasks files.
2. The spec SHALL document the reconciliation rationale and scope.

## Verification

- `swift test` passes.
- `swift build` passes.
- `git diff --check` passes.
- No UI or source code files are changed beyond the spec directory and docs.
