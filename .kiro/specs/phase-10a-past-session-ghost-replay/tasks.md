# Phase 10A - Past-Session Ghost Replay — Tasks

## Task List

### T1: Extend GhostPick with rankedGhostCandidates
- [ ] Add `rankedGhostCandidates(candidates:current:) -> [Workout]`
- [ ] Refactor `pickDefaultGhostCandidate` to return `rankedGhostCandidates(...).first`
- [ ] Handle non-finite distance, duration, pace inputs
- [ ] Add stable ID tie-break

### T2: Create ReplayRaceGap
- [ ] Create `Sources/RowPlayCore/Replay/ReplayRaceGap.swift`
- [ ] Implement `raceGapMeters`, `raceGapSeconds`, `relativeDuration`, `absoluteTime`, `ghostFrame`, `ghostDistance`

### T3: Add Parity Fixture
- [ ] Create `Tests/RowPlayCoreTests/Fixtures/replay-race-gap-parity.json`
- [ ] Register in `Package.swift` resources

### T4: Cache Ghost Candidates in WorkoutLibrary
- [ ] Add `ghostCandidates(for:) -> [WorkoutDetail]`
- [ ] Add `defaultGhostCandidate(for:) -> WorkoutDetail?`
- [ ] Add cache invalidation in `updateAllDerivedData()`

### T5: Wire Production Route in ContentView
- [ ] Pass `library.ghostCandidates(for: workoutID)` to `ReplayView`

### T6: Refactor ReplayView Ghost State
- [ ] Replace `ghostDetail` with `ghostCandidates` + `selectedGhostID`
- [ ] Add `activeGhostDetail` computed property
- [ ] Increment `replayDiscontinuityGeneration` on rival change
- [ ] Clear 2D ghost path on rival change
- [ ] Update all `ghostDetail` references to `activeGhostDetail`

### T7: Add Rival Control Band
- [ ] Add Menu with "No Rival", "Best Match", divider, candidates
- [ ] Add removal button
- [ ] Add live gap display (date, distance gap, time gap)
- [ ] Handle disabled state when no candidates

### T8: Add 2D Ghost Rendering
- [ ] Precompute ghost path from active rival strokes
- [ ] Draw ghost path and playhead on Canvas
- [ ] Update Canvas accessibility

### T9: Update 3D Ghost Sampling
- [ ] Use ReplayRaceGap helpers instead of Replay3DPlayback
- [ ] Clear ghost context on rival change
- [ ] Delete Replay3DPlayback if fully replaced

### T10: Add Tests
- [ ] `ReplayRaceGapTests.swift`
- [ ] `WorkoutLibraryGhostCandidateTests.swift`
- [ ] `ReplayGhostWorkflowTests.swift`
- [ ] Expand `GhostPickTests.swift`
- [ ] Expand `ReplayNavigationTests.swift`
- [ ] Expand `Replay3DSceneEffectsTests.swift`
- [ ] Expand `ReplayQualitySceneTests.swift`

### T11: Update Documentation
- [ ] Update `docs/roadmap.md` with Phase 10A entry
- [ ] Update `docs/source-map.md` with new files
- [ ] Update `docs/beta-readiness.md` removing production-route ghost gap
- [ ] Update this tasks.md with completion status

### T12: Validate
- [ ] Focused test suite pass
- [ ] Complete matrix: swift test, swift build, git diff --check
- [ ] Architecture scans (no forbidden imports)
- [ ] Bundle gates: --verify, --automation, --sign-verify
