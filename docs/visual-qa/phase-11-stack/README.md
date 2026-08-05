# Phase 11 Replacement Stack QA

Phase 11 merged to `main` through PRs #90–#97. The final layer owns the complete
automated acceptance matrix; lower layers provide targeted evidence only. This
record deliberately separates reproducible scene validation from human
screenshot review.

## Reproducible matrix

`Phase11SceneAcceptanceTests` constructs and updates two complementary 48-case
matrices:

- 48 procedural-path cases cover three sports, four quality tiers, and four
  camera presets. They vary viewport aspect and rival visibility/pose inputs,
  then verify the shared render predicate, full resolved camera pose, and
  authored FOV for each wiring case.
- 48 asset-supplied cases cover three sports, four tiers, light/dark themes,
  and rival absent/present under Reduced Motion. Low/Medium assert the intended
  procedural policy; High/Ultra assert the production bundled athlete and
  equipment path. Repeated exact seeks require identical live, rival, and
  camera transforms, sport-static Reduced Motion FOV, and chase-rival framing.

The scene-effects suite separately proves that a requested rival with no
sampled pose cannot enable the ghost rig, influence the camera, or emit ghost
effects. Portable camera tests cover viewport sanitization plus padded
camera-space frustum inclusion for equal-distance, gapped, and opposite-course
rivals in portrait, default, and ultrawide viewports.

The surrounding focused suites prove current motion fixtures, equipment
contracts, atomic athlete/equipment/environment fallback, hand/grip contact,
effect budgets, accessibility, and 2D rendering. `Replay2DSceneTests` can emit
six 960x460 captures when `ROWPLAY_CAPTURE_2D_QA_DIR` is set; capture generation
is automated, but pixel-level human approval is not inferred from a test pass.

## Staged application

The final stack must use `./script/build_and_run.sh --verify`; launching the raw
SwiftPM executable is not valid evidence. The staged bundle gate proves only
that the signed `.app` launches. Exact-head macOS/Linux CI and unresolved
review threads remained merge-time gates for each PR.

## Human verification boundary

The automated matrices do not prove final pixels, interaction feel, or sustained
GPU performance. Phase 12 owns that staged-app human walkthrough and profiling
release gate; see `docs/visual-qa/phase-12-replay-acceptance/`.

## Claim boundary

Task 8 records that the final stack layer and automated matrix exist and that
PRs #90–#97 merged. Phase 11 does not by itself claim completed human visual
acceptance or sustained GPU profiling; those are Phase 12 deliverables.
