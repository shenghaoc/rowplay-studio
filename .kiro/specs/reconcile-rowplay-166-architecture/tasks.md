# Reconcile RowPlay Studio With rowplay PR #166 — Tasks

- [x] Verify rowplay PR #166 is merged.
- [x] Update web source repo to post-PR-166 main.
- [x] Create `codex/reconcile-rowplay-166-architecture` branch.
- [x] Create `.kiro/specs/reconcile-rowplay-166-architecture/` spec.
- [x] Update `docs/roadmap.md`: add Web Architecture Baseline section and
  review all phases for stale KV/D1/sync/feature language.
- [x] Update `docs/source-map.md`: mark retired web files, label native
  SQLite as native-only, add remove-kv-d1 spec reference.
- [x] Update `docs/beta-readiness.md`: add PR #166 impact section.
- [x] Update `.kiro/steering/structure.md`: remove stale KV/D1 porting
  guidance.
- [x] Update `AGENTS.md`: verify WorkoutCache production status.
- [x] Update historical Kiro phase specs: mark pre-PR-166 KV/D1 references as
  historical and retire comparison, annotations, and sharing as web-parity
  targets.
- [x] Validate: `swift test`, `swift build`, `git diff --check`.
