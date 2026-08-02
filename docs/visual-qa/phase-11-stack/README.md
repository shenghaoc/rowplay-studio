# Phase 11 Replacement Stack QA

The final layer owns the complete acceptance matrix; lower layers provide
targeted evidence only. This record deliberately separates reproducible scene
validation from human screenshot review.

## Reproducible matrix

`Phase11SceneAcceptanceTests` constructs and updates 48 combinations: three
sports, four quality tiers, and four camera presets. Every case includes an
independent live/rival pair and the complete venue contract. A second matrix
repeats exact seeks with Reduced Motion for all sports and requires identical
live, rival, and camera transforms.

The surrounding focused suites prove current motion fixtures, equipment
contracts, atomic athlete/equipment/environment fallback, hand/grip contact,
effect budgets, accessibility, and 2D rendering. `Replay2DSceneTests` emits six
960x460 captures when `ROWPLAY_CAPTURE_2D_QA_DIR` is set; the RowErg water,
SkiErg snow, and BikeErg velodrome captures were inspected on the final stack.

## Staged application

The final stack must use `./script/build_and_run.sh --verify`; launching the raw
SwiftPM executable is not valid evidence. The staged bundle gate proves the
signed `.app` launches. Exact-head macOS/Linux CI and unresolved review threads
remain merge-time gates for each PR.

## Claim boundary

Checking task 8 records that the final stack layer exists and its local matrix
passes. It does not mean Phase 11 is shipped: the phase becomes complete only
after PRs 1 through 8 merge bottom-up and each descendant is restacked and
revalidated at its new exact head.
