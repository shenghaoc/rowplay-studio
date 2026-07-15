# Phase 10A - Past-Session Ghost Replay — Tasks

## Task List

### T1: Extend GhostPick with rankedGhostCandidates
- [x] Add `rankedGhostCandidates(candidates:current:) -> [Workout]`
- [x] Refactor `pickDefaultGhostCandidate` to return `rankedGhostCandidates(...).first`
- [x] Handle non-finite distance, duration, pace inputs
- [x] Add stable ID tie-break

### T2: Create ReplayRaceGap
- [x] Create `Sources/RowPlayCore/Replay/ReplayRaceGap.swift`
- [x] Implement `raceGapMeters`, `raceGapSeconds`, `relativeDuration`, `absoluteTime`, `ghostFrame`, `ghostDistance`

### T3: Add Parity Fixture
- [x] Create `Tests/RowPlayCoreTests/Fixtures/replay-race-gap-parity.json`
- [x] Register in `Package.swift` resources

### T4: Cache Ghost Candidates in WorkoutLibrary
- [x] Add `ghostCandidates(for:) -> [WorkoutDetail]`
- [x] Add `defaultGhostCandidate(for:) -> WorkoutDetail?`
- [x] Add cache invalidation in `updateAllDerivedData()`

### T5: Wire Production Route in ContentView
- [x] Pass `library.ghostCandidates(for: workoutID)` to `ReplayView`

### T6: Refactor ReplayView Ghost State
- [x] Replace `ghostDetail` with `ghostCandidates` + `selectedGhostID`
- [x] Add `activeGhostDetail` computed property
- [x] Increment `replayDiscontinuityGeneration` on rival change
- [x] Clear 2D ghost path on rival change
- [x] Update all `ghostDetail` references to `activeGhostDetail`

### T7: Add Rival Control Band
- [x] Add Menu with "No Rival", "Best Match", divider, candidates
- [x] Add removal button
- [x] Add live gap display (date, distance gap, time gap)
- [x] Handle disabled state when no candidates

### T8: Add 2D Ghost Rendering
- [x] Precompute ghost path from active rival strokes
- [x] Draw ghost path and playhead on Canvas
- [x] Update Canvas accessibility

### T9: Update 3D Ghost Sampling
- [x] Use ReplayRaceGap helpers instead of Replay3DPlayback
- [x] Refresh ghost context on rival change
- [x] Delete Replay3DPlayback after full replacement

### T10: Add Tests
- [x] `ReplayRaceGapTests.swift`
- [x] `WorkoutLibraryGhostCandidateTests.swift`
- [x] `ReplayGhostWorkflowTests.swift`
- [x] Expand `GhostPickTests.swift`
- [x] Expand `ReplayNavigationTests.swift`
- [x] Expand `Replay3DSceneEffectsTests.swift`
- [x] Expand `ReplayQualitySceneTests.swift`

### T11: Update Documentation
- [x] Update `docs/roadmap.md` with Phase 10A entry
- [x] Update `docs/source-map.md` with new files
- [x] Update `docs/beta-readiness.md` removing production-route ghost gap
- [x] Update this tasks.md with completion status

### T12: Validate
- [x] Focused test suite pass
- [x] Complete matrix: swift test, swift build, git diff --check
- [x] Architecture scans (no forbidden imports)
- [x] Bundle gates: --verify, --automation, --sign-verify
