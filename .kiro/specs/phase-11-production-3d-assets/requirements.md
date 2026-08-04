# Phase 11 — Current RowPlay Parity: Requirements

Phase 11 catches the native app up to current RowPlay `main` — not the
historical PR #171 / V4-mannequin milestone it originally targeted.  The
authoritative reference is the exact pinned `main` commit recorded in
`Sources/RowPlayStudio/Resources/ReplayReference/rowplay-source.json`.

## R1 — Pinned current-main reference bundle

1.1 All replay reference artifacts (athlete GLB/USDZ + contract, motion table,
equipment packages, environment maps, parity fixtures) are read from one
pinned RowPlay `main` git tree, never from a working directory. The original
athlete USDZ and contract remain the immutable native source reference.
1.2 Every manifest records the pinned commit, source paths, SHA-256 and
sizes. The native athlete derivative additionally seals both pinned GLB/USDZ
inputs, its deterministic converter, surface partition, and output hash;
`script/validate_rowplay_reference.py` verifies committed-bundle consistency
without the sibling checkout.
1.3 No runtime downloads; the bundle ships in the app.

## R2 — Production athlete activation

2.1 The production anatomical athlete (19 semantic bones + 32 visual grip
helpers = 51 joints, one skinned mesh) loads, validates against the live
contract — not a hard-coded name list — and activates at every quality tier.
Its deterministic native derivative binds eight actual material subsets in
contract order: skin, jersey/fabric, lower/shorts, footwear, hair, trim, eye,
and face detail. These bindings are production geometry at Low through Ultra,
not test-only metadata or a one-material placeholder.
2.2 Base motion is driven from the sampled `rowplay-motion.bin` table
(≥257 phases per sport, linear translation/scale, shortest-path normalized
rotation interpolation), never from `availableAnimations` clip names.
2.3 Every seek rebuilds the pose from the bind pose plus the table: direct
and shuffled seeks are deterministic; no state accumulates.
2.4 Contact correction applies only after base-pose sampling; digit closure
rides the corrected hands.
2.5 Live and rival instances keep independent skeletons, helpers, materials
and motion state.  Failure at any gate falls back atomically to the complete
procedural scene.
2.6 Portable cold-load work (file reads, SHA-256, JSON parsing, and motion
table validation) executes off `MainActor`; only RealityKit entity/resource
creation and cache installation return to `MainActor`.

## R3 — Grip system

3.1 The hand grip channel model and digit-closure solver are ported to
RowPlayCore as portable, unit-testable math (`ReplayGripGeometry`,
`ReplayHandClosure`, `ReplayGripSurface`) with the sport contracts
(`ReplayRowGripContract`, `ReplaySkiGripContract`, `ReplayBikeGripContract`).
3.2 RowErg: each hand encloses its own 23 mm scull rubber; the thumb closes
on the flat handle end; sequential first-contact closure.
3.3 SkiErg: both fists close on independent 16 mm pole grips with thumb
opposition 1.75; sequential first-contact closure.
3.4 BikeErg: palms are supported on the 18 mm hood bodies with the wrapped
final-enclosure search; four fingers reach the far side, the thumb hooks
underneath.
3.5 Closures are solved once at install and cached; per-frame work applies
cached helper rotations only.

## R4 — 2D replay scenes

4.1 2D replay is a sport scene, not a timeline/dot: real course, live and
optional rival, start/finish and progress cues, equipment, articulated
participant, current movement phase.  Any time/distance graph is only a
secondary overlay.
4.2 RowErg: racing shell, aft-facing rower, sliding seat, fixed stretcher,
two rigid sculls through oarlocks, blade square/feather, drive/recovery
sequencing from the motion graph.
4.3 SkiErg: course skier with parallel skis, boots, two poles with grips and
baskets; planted baskets stay course-fixed through the loaded interval; no
indoor tower/cable/platform.
4.4 BikeErg: road bicycle with correctly signed distance-driven wheel
rotation and cadence-driven opposed cranks, in the indoor timber velodrome.
4.5 One motion source (`ReplayMotionGraph`); no second animation clock.

## R5 — Equipment

5.1 Equipment dimensions come from the ported Core contracts: RowErg single
scull (oarlocks ±0.88 m at 0.51 m, scull grips 23 mm with thumb stops,
stretcher −48°), SkiErg (1.90 m skis, 1.37 m rigid poles, plant 0.46 m
lateral / 0.24 m forward), BikeErg (0.670 m wheels, ≈0.999 m wheelbase, 73°
head/seat angles, 30° knee flexion at BDC, analytic winged/cut-out saddle).
5.2 High and Ultra use the converted authored V3 composites (Blender
conversion preserving names/transforms/bounds; sidecar contracts; fail on
missing or duplicated parts).  Low and Medium use procedural equipment built
from the same contracts.
5.3 No central indoor-rower handle; no SkiErg machine in the course scene;
the athlete is never scaled to fit equipment.

## R6 — Environments and quality tiers

6.1 The three venue stories are ported natively: RowErg morning-glass regatta
basin; SkiErg blue-hour Nordic stadium; BikeErg evening indoor velodrome with
the black/red/blue/côte-d'azur line grammar.
6.2 Quality tiers follow the current contract: the validated production
athlete is active at every tier; authored equipment is active at High/Ultra,
while Low/Medium intentionally use contract-driven procedural equipment.  The
complete procedural athlete-and-equipment renderer is a failure fallback only.
Adjacent tiers are materially different (feature counts, texture usage: CC0
maps at High, +normal maps at Ultra; athlete detail maps 128/256/512 px at
Medium/High/Ultra and no athlete detail allocation at Low). Athlete detail
resources are deterministic, process-shared between live/rival instances, and
paired with per-role PBR response at every tier.
6.3 The six-file USDA rig/environment package is removed.

## R7 — Camera, rival, fallback

7.1 Sport-specific rear three-quarter chase rigs (rower 4.05/1.78/0.88/2.16
aim 0.84 FOV 40; ski 3.15/2.3/0.9/1.86 aim 1.14 FOV 42; bike
3.12/1.96/0.58/1.92 aim 0.92 FOV 42) with speed FOV breathing (+2°) and
rival pullback (flat 1.05 m plus span-fitted framing of the pair midpoint).
7.2 Reduced Motion pins the FOV, widens the static frame, snaps the camera,
and uses one representative pose per sport without hiding the subject.
7.3 The rival's skinned body stays opaque, cool-tinted (34 % toward the ghost
teal), depth-tested and depth-writing; rival equipment may use controlled
translucency.
7.4 Loading or runtime failure switches the entire inner replay graph to the
complete procedural fallback, preserving time, play/pause, speed, camera,
quality preference and rival selection; permanent failures are cached.

## R8 — Tests and parity

8.1 Web-parity fixtures are regenerated from the pinned tree with source
commit, file hashes, generator version and sample counts; CI consumes only
committed fixtures.
8.2 Coverage includes: motion-graph channel parity, grip closure parity for
both hands of all three sports, equipment constant/function parity, 2D
kinematics parity, athlete activation/determinism/independence, eight runtime
surface bindings, the 0/128/256/512 athlete detail ladder, off-main cold-load
preflight, fallback atomicity, camera framing, Reduced Motion, and finite
transforms across dense cycles.

## R9 — Privacy and accessibility

9.1 Synthetic demo data only; no workout IDs, user-derived filenames,
absolute filesystem paths, tokens or user metrics in generated manifests.
Pinned repo-relative provenance paths required by R1.2 are allowed;
`PrivacySafeLogger` categories only.
9.2 2D and 3D each expose one meaningful semantic replay element (sport,
time, progress, pace, rival, gap); decorative drawing stays hidden from
VoiceOver; controls remain keyboard operable in every quality/fallback state.
