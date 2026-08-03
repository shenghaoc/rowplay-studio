# Phase 11 Replacement Stack QA

The final layer owns the complete acceptance matrix; lower layers provide
targeted evidence only. This record deliberately separates reproducible scene
validation from human screenshot review.

## Reproducible matrix

`Phase11SceneAcceptanceTests` constructs and updates 96 combinations in two
independent matrices:

- 48 procedural-path cases cover three sports, four quality tiers, and four
  camera presets with an independent live/rival pair.
- 48 asset-supplied cases cover three sports, four tiers, light/dark themes,
  and rival absent/present under Reduced Motion. Low/Medium assert the intended
  procedural policy; High/Ultra assert the production bundled athlete and
  equipment path. Repeated exact seeks require identical live, rival, and
  camera transforms, sport-static Reduced Motion FOV, and rival pullback.

The scene-effects suite separately proves that a requested rival with no
sampled pose cannot enable the ghost rig, influence the camera, or emit ghost
effects. Portable camera tests cover viewport sanitization plus portrait
and ultrawide rival framing.

The surrounding focused suites prove current motion fixtures, equipment
contracts, atomic athlete/equipment/environment fallback, hand/grip contact,
effect budgets, accessibility, and 2D rendering. `Replay2DSceneTests` can emit
six 960x460 captures when `ROWPLAY_CAPTURE_2D_QA_DIR` is set; capture generation
is automated, but pixel-level human approval is not inferred from a test pass.

## Staged application

The final stack must use `./script/build_and_run.sh --verify`; launching the raw
SwiftPM executable is not valid evidence. The staged bundle gate proves only
that the signed `.app` launches. Exact-head macOS/Linux CI and unresolved
review threads remain merge-time gates for each PR.

## Human verification boundary

The automated matrices do not prove final pixels, interaction feel, or sustained
GPU performance. A staged-app walkthrough across 2D/3D, all sports, both themes,
rival off/on, all camera presets, all tiers, Reduced Motion, and supported
window extremes remains unperformed unless a dated evidence record is added.
No screenshot or manual-approval claim is made by this file.

## Claim boundary

Checking task 8 records that the final stack layer and automated matrix exist.
It does not mean Phase 11 is accepted or shipped: the phase becomes complete only
after PRs 1 through 8 merge bottom-up and each descendant is restacked and
revalidated at its new exact head, with the human boundary above either
completed or explicitly accepted by the owner.
