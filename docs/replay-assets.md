# Replay 3D Assets

## Current Status

Phase 11 is implemented on RowPlay Studio PR #72. On the local PR head, the
deterministic generator check, focused asset/rig/scene suites, full `swift
test` (1,196 tests total: 978 Core, 68 Platform, and 150 Studio; two expected
Core skips), `swift build`, architecture scans,
whitespace check, staged-bundle resource check, staged launch, automation
launch, and signature verification pass. GitHub CI on the exact pushed head is
a separate PR gate; its current result is recorded on PR #72.

The staged app was checked with RowErg, SkiErg, and BikeErg at low, medium,
high, and ultra. Low visibly selects the complete existing procedural rig and
background; valid higher tiers select the complete bundled sport set. A
BikeErg Low-to-Medium change preserved the seek position, and pause/resume
continued to work. Captured visual review covered representative bundled and
procedural scenes, all four camera choices, a live participant, past-session
and constant-pace rivals, dark and light appearance, automation/Reduced Motion,
and the largest and compact windows available in this environment. Native
accessibility inspection exposed clear labels, values, and help for the replay,
camera, quality, rival, and playback controls.

A real imported-rival CSV was visible in the native file panel, but the desktop
QA bridge could not perform the final file selection in this run. The unchanged
bounded importer and the Phase 11 imported-rival 3D identity/fallback path are
covered by the current focused tests, and the native panel import flow was
already exercised when that workflow landed in Phase 10B. Not available for
this phase: a spoken VoiceOver pass, pointer/trackpad orbit gesture proof,
Instruments, and GPU profiling.

Phase 11 is native-owned. The app bundles project-generated USD assets for the
macOS runtime, while the replay clock, pose solver, course, cameras, effects,
quality policy, equipment contacts, and procedural fallback remain native
systems. There is no runtime download or separately maintained web dependency.

## Art Direction

The target is a coherent, non-photorealistic athlete and equipment family that
reads well at replay scale:

- Rounded, tapered athlete anatomy with a clear head/hair, kit, hands, shoes,
  and continuous joints rather than box/cylinder/sphere assemblies.
- RowErg: recognisable hull, rail, seat, footplate, handle, and paired oars,
  framed by water, shoreline, buoys, dock, and restrained vegetation.
- SkiErg: recognisable upright frame, handles, poles, cable, and platform,
  framed by snow, conifers, gates, and snowbanks.
- BikeErg: recognisable frame, wheels, cranks, pedals, saddle, and handlebar,
  framed by a paved or velodrome-style course with barriers, banners, and
  trackside depth.
- A restrained material palette that distinguishes base, accent, metal, trim,
  and environment surfaces without custom shaders, brands, trademarks, copied
  logos, scans, or external model content.

The asset files contain no cameras or lights. Native camera, lighting, 400 m
course coordinates, lanes, start/finish marker, distance markers, wake, and
catch effects remain authoritative.

## Resources and Generation

The generated resources are expected at:

```text
Sources/RowPlayStudio/Resources/Replay3D/
├── rower-rig.usda
├── skierg-rig.usda
├── bike-rig.usda
├── rower-environment.usda
├── skierg-environment.usda
├── bike-environment.usda
└── ASSET_PROVENANCE.md
```

Regenerate them with:

```bash
python3 script/generate_replay_assets.py
```

Check that committed output and its contract are current without rewriting
files:

```bash
python3 script/generate_replay_assets.py --check
```

The generator uses only the Python standard library, fixed input ordering, and
deterministic geometry. It must not use the network. Commit the generator and
the generated ASCII USDA files together; do not replace them with opaque or
third-party binary models. `ASSET_PROVENANCE.md` is the authoritative record
of ownership and regeneration inputs.

## Contract

`ReplayAssetCatalog` is the single source of truth for every resource name,
sport association, node requirement, material category, expected bound, and
budget. `Tests/RowPlayStudioTests/Fixtures/replay-asset-contract.json` mirrors
the contract for deterministic tests; it is not a claim of web numerical
parity.

All rig files must contain:

```text
visual-pelvis             visual-torso              visual-head
visual-upperArm-L         visual-forearm-L          visual-hand-L
visual-upperArm-R         visual-forearm-R          visual-hand-R
visual-thigh-L            visual-shin-L             visual-foot-L
visual-thigh-R            visual-shin-R             visual-foot-R
```

Sport-specific rig nodes are:

| Sport | Required nodes |
| --- | --- |
| RowErg | `visual-hull`, `visual-deck-stripe`, `visual-footplate`, `visual-rail`, `visual-seat`, `visual-handle`, `visual-oar-port`, `visual-oar-starboard` |
| SkiErg | `visual-post-L`, `visual-post-R`, `visual-topBar`, `visual-platform`, `visual-handle-L`, `visual-handle-R`, `visual-pole-L`, `visual-pole-R`, `visual-cable` |
| BikeErg | `visual-wheel-front`, `visual-wheel-rear`, `visual-downTube`, `visual-seatTube`, `visual-topTube`, `visual-cranks`, `visual-chainRing`, `visual-pedal-L`, `visual-pedal-R`, `visual-handlebar`, `visual-saddle` |

Every environment contains `environment-root`, `environment-ground`, and
`environment-props`.

Material categories use the following stable vocabulary:

| Asset | Categories | Use |
| --- | --- | --- |
| Every rig | `skin`, `hair`, `kit`, `shoe`, `accent`, `metal`, `rubber` | Athlete anatomy, kit, footwear, accent panels, hardware, and grips/tyres. |
| RowErg environment | `water`, `shore`, `foliage`, `accent`, `metal` | Water course, shoreline, vegetation, buoys/dock details. |
| SkiErg environment | `snow`, `ice`, `foliage`, `accent`, `metal` | Snow course, ice, conifers, gates, and hardware. |
| BikeErg environment | `asphalt`, `concrete`, `accent`, `metal`, `foliage` | Track, barriers, banners, and trackside depth. |

The generator names each authored accent mesh `material_accent_*`. During rig
construction the bundled provider recolours only those named slots on the
scene-local live or rival clone; it does not infer roles from rendered colour
or mutate the cached template.

Node names describe geometry only. Native named pivots own animation and
contacts. Do not add an asset-local pose controller or a second animation
system.

## Budgets and Validation Rules

| Rule | Limit |
| --- | ---: |
| One rig asset | at most 18,000 triangles |
| One environment asset | at most 30,000 triangles |
| All six assets | below 15 MiB |
| Geometry | non-empty, finite transforms and normals |
| Required nodes | present and unique |
| Cameras and lights in assets | none |

A complete sport set must validate before it is used. Missing, corrupt,
malformed, or incomplete content does not permit a partial mix of bundled and
procedural limbs, equipment, or scenery.

## Runtime Provider Model

`ReplayRigVisualProvider` separates native pose ownership from geometry choice:

```text
ReplaySportRig (pivots, contacts, applyPose)
        └── ReplayRigVisualProvider
            ├── ReplayProceduralRigVisualProvider
            └── ReplayBundledRigVisualProvider
                    └── ReplayAssetLibrary / Bundle.module
```

The procedural provider explicitly selects the existing generated meshes still
owned by each articulated rig; it does not duplicate those builders. The
bundled provider validates a resource template once, clones it recursively,
and maps its visual nodes to the same logical pivots. Templates, live rigs,
rivals, and scenes must never share mutable materials or animation state.

`ReplayEnvironmentAssetInstaller` adds a bundled background only during scene
construction. It leaves native lanes, distances, markers, lights, cameras, and
effects in place and suppresses only the generic procedural background that it
replaces.

## Quality and Fallback

| Effective quality | Athlete/equipment | Environment |
| --- | --- | --- |
| Low | Existing complete procedural rig | Existing procedural background |
| Medium / High / Ultra | Validated complete bundled sport set | Matching bundled environment |
| Any validation/load failure | Complete procedural fallback | Complete procedural fallback |

The existing inner quality-graph rebuild chooses this source. It must preserve
replay time, play/pause state, speed, camera preset, orbit state, and rival
selection. Resource loading and hierarchy traversal are prohibited in per-frame
updates.

Ghost translucency must cover every loaded material type, including PBR-style
materials. A rival material mutation must never affect the live participant,
cached template, or another scene. Imported and constant-pace rivals continue
to use the existing fallback articulation, and Reduced Motion continues to
produce stable neutral poses with the established effect suppression.

## Safe Replacement or Extension

1. Keep the generator deterministic and update it before manually changing a
   generated USDA file.
2. Update `ReplayAssetCatalog` and the golden contract before adding/removing a
   node, resource, material category, bound, or budget.
3. Retain every required visual node and attach it to its existing logical
   pivot; do not move pose/contact ownership into the asset.
4. Preserve the size/triangle limits and add a focused regression test for the
   changed contract.
5. Keep resources project-authored or stop until external redistribution rights
   are established and documented.
6. Run `--check`, focused asset tests, the full build/test matrix, and staged
   bundle inspection before describing a change as validated.

Visual acceptance requires more than successful loading. Inspect silhouette,
recognisability, material coherence, environment depth, articulation/contact,
camera framing, ghost translucency, reduced motion, and all sport/quality
paths in the staged app. Record unavailable visual, VoiceOver, gesture,
screen-size, Instruments, or GPU evidence plainly.
