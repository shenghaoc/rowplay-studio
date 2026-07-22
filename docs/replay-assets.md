# Replay 3D Assets

## Current Status

Phase 11 is implemented on RowPlay Studio PR #72 (**draft**), titled
`Phase 11: Match native replay to merged RowPlay V4`.

The integration is pinned to the final merged RowPlay PR #171 commit:

```text
da0dc73bf295871e9b362511cd5b2c9a9424b325
```

`script/sync_rowplay_athlete.py` reads that exact Git tree, verifies that the
commit is reachable from `rowplay`'s `origin/main`, verifies every copied
hash, and records a `merged` source manifest. It never reads a local RowPlay
working-tree `HEAD`.

| Artifact | SHA-256 |
| --- | --- |
| GLB | `73e0ece3e6c6de5a7a020a5097b172ca3e0ed8315c27ff604159b144fa90547b` |
| USDZ | `934b0d3af0454f60a84dde76f95b77121919f5ad7cfc366684a670ae5d99658e` |
| Contract | `e9fb56f372ac1ea44ee5ccaf1d00b5a975e1eb4a1a2ee7843ab9e53609fb189d` |

## Hard Runtime Gate

The final upstream contract requires one exact animation resource for each
sport:

| Sport | Required resource name |
| --- | --- |
| RowErg | `rowplay-v4-row-cycle` |
| SkiErg | `rowplay-v4-ski-cycle` |
| BikeErg | `rowplay-v4-bike-cycle` |

The exact final USDZ does not provide those RealityKit animation-resource
names. Its USD content contains only an authored row animation named
`rowplay_v4_row_cycle` (underscore spelling), with no SkiErg or BikeErg
counterparts. This is an upstream artifact/contract inconsistency, not a
native aliasing issue.

Studio deliberately rejects the complete V4 package when that gate fails:

- it does not select `availableAnimations.first`;
- it does not translate underscore names or reuse the row animation for other
  sports;
- it does not mix a rejected V4 body with bundled equipment or environments;
- Medium, High, and Ultra rebuild as the complete procedural scene, preserving
  replay state and camera state; Low remains procedural by design.

The strict rejection is covered by `ReplayAthleteLibraryTests` and
`ReplayBundledSportRigTests`. It is the correct current behavior, but it also
means PR #72 cannot be marked ready or claimed as a successful V4 runtime
handoff until the upstream source is internally consistent. The required
upstream resolution is a corrected final USDZ with the three contract-named
clips, or an upstream contract/artifact revision with matching hashes. A local
compatibility alias would violate the Phase 11 contract and is intentionally
not an acceptable substitute.

## Ownership

| Asset class | Owner | Location |
| --- | --- | --- |
| V4 skinned athlete, skeleton, animation contract | Merged RowPlay PR #171 | Synced into `Resources/Replay3D/rowplay-athlete-v4.*` |
| Equipment geometry (RowErg / SkiErg / BikeErg) | RowPlay Studio | Generated `*-rig.usda` |
| Sport environments | RowPlay Studio | Generated `*-environment.usda` |
| Replay clock, cameras, lights, effects, course | RowPlay Studio | Existing native systems |
| Low / validation-failure athlete | RowPlay Studio | Procedural `ReplayAthleteRig` |

## Synchronisation

```bash
python3 script/sync_rowplay_athlete.py \
  --rowplay-repo /path/to/rowplay \
  --expected-commit da0dc73bf295871e9b362511cd5b2c9a9424b325

python3 script/sync_rowplay_athlete.py \
  --rowplay-repo /path/to/rowplay \
  --expected-commit da0dc73bf295871e9b362511cd5b2c9a9424b325 \
  --check
```

The source manifest is the runtime authority for the commit and SHA-256
values. Runtime code validates its schema, `merged` status, repository and PR
identity, and copied USDZ/contract hashes before RealityKit loading.

## Native Motion and Constraints

The portable Core layer ports the canonical V4 motion graph, sport kinematics,
and two-bone solver. The committed parity fixture has 129 phase samples per
sport (387 samples total), generated from the pinned upstream Git tree; the
test compares native channels to that source without a hand-maintained
approximation.

When a corrected V4 template passes the clip gate, Studio seeks its exact
sport clip from the native replay clock, then runs one deterministic skeletal
pass in this order:

```text
prepare -> orientHandsToTargets -> constrain
```

The pass restores the base root placement on each seek/frame, adjusts pelvis
translation and arm/leg chains from `SkeletalPosesComponent`, applies terminal
orientations and per-limb branch hints, and uses contact markers only as
diagnostic mirrors. It does not snap a marker to an equipment target. Rival V4
bodies use an opaque, depth-writing cool tint; only their equipment remains
translucent.

## Quality and Fallback

| Quality / state | Athlete | Equipment / environment |
| --- | --- | --- |
| Low | Existing procedural | Existing procedural |
| Medium / High / Ultra, complete validated package | Canonical V4 | Native bundled USDA |
| Any source, contract, clip, or runtime failure | Complete procedural | Complete procedural |

The fallback is scene-wide and state-preserving. It never changes replay time,
play state, speed, camera preset/orbit state, or rival selection.

## Equipment Generation

```bash
python3 script/generate_replay_assets.py
python3 script/generate_replay_assets.py --check
```

Resources:

```text
Sources/RowPlayStudio/Resources/Replay3D/
├── rower-rig.usda / skierg-rig.usda / bike-rig.usda
├── rower-environment.usda / skierg-environment.usda / bike-environment.usda
├── rowplay-athlete-v4.usdz
├── rowplay-athlete-v4.contract.json
├── rowplay-athlete-v4-source.json
└── ASSET_PROVENANCE.md
```

Phase 12 remains the future premium anatomy/deformation work. It must reuse
this sync, validation, motion, and fallback boundary rather than bypass it.
