# Phase 10A - Past-Session Ghost Replay — Requirements

## Purpose
Expose comparable past workouts as user-selectable replay rivals through the production navigation route, with deterministic best-match ranking, live ahead/behind gap presentation, and 2D/3D rival rendering.

## Requirements

### R1: Ranked Ghost Candidates
- Ranked comparable past-session candidates via `GhostPick.rankedGhostCandidates`.
- Deterministic best match via `rankedGhostCandidates(...).first`.
- Exclude current workout, no-stroke candidates, different sports, and non-comparable workouts.
- Distance-axis ranking: matching band → closest distance → fastest pace → most recent → stable ID tie-break.
- Time-axis ranking: matching band → closest duration → fastest pace → most recent → stable ID tie-break.
- Sanitize non-finite values.

### R2: Race-Gap Helpers
- `raceGapMeters(playerDistance:ghostDistance:)` — positive = player ahead.
- `raceGapSeconds(gapMeters:playerPacePer500m:)` — approximate seconds.
- `relativeDuration(strokes:)` — duration from first to last stroke.
- `absoluteTime(elapsed:strokes:)` — convert elapsed replay time to absolute stroke time.
- `ghostFrame(elapsed:strokes:)` — interpolated ghost frame at player elapsed time.
- `ghostDistance(elapsed:strokes:)` — ghost distance at player elapsed time.
- Non-positive pace produces zero seconds. Non-finite input produces finite fallback.
- Empty stroke arrays produce safe zero/empty results. Non-zero first timestamps handled.
- Clamp elapsed time to ghost relative duration.

### R3: Parity Fixture
- Golden JSON fixture verifying race-gap calculations against web parity.
- Coverage: ahead, behind, tied, positive/negative seconds, zero pace, interpolation, clamping.

### R4: Cached Candidates in WorkoutLibrary
- `ghostCandidates(for:)` and `defaultGhostCandidate(for:)` APIs.
- Cache by active workout ID, invalidated on details change.
- Use `GhostPick.rankedGhostCandidates` and resolve to `WorkoutDetail`.
- Exclude empty-stroke details even if `hasStrokeData` is true.
- Full-library behavior independent of active filter/sport.

### R5: Production Route Wiring
- `ContentView` passes `ghostCandidates` to `ReplayView` in the `.replay` navigation destination.
- No candidate derivation in SwiftUI body. No second navigation route.

### R6: ReplayView Ghost State Refactor
- Replace `ghostDetail: WorkoutDetail?` with `ghostCandidates: [WorkoutDetail]` + `selectedGhostID: Int?`.
- Computed `activeGhostDetail` resolves from the fixed candidate snapshot.
- Changing rival increments `replayDiscontinuityGeneration`, clears 2D ghost path, rebuilds 3D child scene.
- Preserve time, playing state, speed, renderer mode, camera, quality on rival change.

### R7: Rival Control
- Full-width band below renderer picker and above replay surface.
- `Menu` with `person.2.fill` symbol. Items: "No Rival", "Best Match", divider, ranked candidates.
- Candidate labels show date, distance, pace. Checkmark for current selection.
- Icon-only `xmark.circle` removal button. Disabled when no candidates.
- Live gap display: date, distance gap, approximate time gap with color coding.

### R8: 2D Ghost Rendering
- Precomputed ghost path and playhead drawn on Canvas.
- Ghost path uses `AppDesign.softPurple` with restrained opacity.
- Live path remains visually dominant.
- Ghost playhead sampled at player's current elapsed time.
- Uses player workout's chart scales for direct comparability.

### R9: 3D Ghost Sampling Consolidation
- Use `ReplayRaceGap.absoluteTime`/`ghostFrame` instead of duplicate `Replay3DPlayback.absoluteTime`.
- Preserve independent ghost pose, translucency, lane, wake, quality, motion, camera behavior.
- Clear old wake/effect history on rival change.
- Rival shorter than player stays at finish position; longer rival correctly sampled at player finish.

### R10: Tests
- Core: ranked ordering, exclusions, axis filtering, non-finite inputs, gap math, parity fixture.
- Platform: detail resolution, empty-stroke exclusion, cache reuse/invalidation.
- Studio: ReplayView construction, rival selection/removal, scene identity, path generation, gap formatting.

### R11: Documentation
- Update roadmap, source-map, beta-readiness with Phase 10A entries.
- Correct stale Phase 8D language. List explicit remaining exclusions.

## Non-Goals (Phase 10A)
- Constant-pace rival generation, pace input UI, CSV/TCX/FIT import, file panels.
- Race result verdict, race-card download/sharing, URL/deep-link rival state.
- Persisted rival selection, network requests, imported 3D assets, rig redesign.
- Bluetooth/CoreBluetooth, OAuth, external dependencies, toolchain upgrades.
