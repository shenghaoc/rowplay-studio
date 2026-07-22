# Replay 3D Assets

## Current Status

Phase 11 is implemented on RowPlay Studio PR #72 (**draft**):
`Phase 11: Align native replay with the canonical RowPlay athlete`.

Upstream athlete ownership is provisional rowplay PR #171 at commit
`dba7211bfa94d3f86e60b75921bd5853ec736f55`. PR #72 implements and tests against
that snapshot but must not merge before PR #171. Refreshing the pin is
mechanical via `script/sync_rowplay_athlete.py`.

Phase 11 establishes production-grade **integration**, validation, quality
selection, and fallback. It does **not** claim that V4 is the final premium
athlete. Premium anatomy, deformation, clothing, and most interpenetration
(`穿模`) work are **Phase 12**.

## Ownership

| Asset class | Owner | Location |
| --- | --- | --- |
| V4 skinned athlete, skeleton, animations, landmarks | Upstream rowplay PR #171 | Synced into `Resources/Replay3D/rowplay-athlete-v4.*` |
| Equipment geometry (RowErg / SkiErg / BikeErg) | RowPlay Studio | Generated `*-rig.usda` |
| Sport environments | RowPlay Studio | Generated `*-environment.usda` |
| Replay clock, cameras, lights, effects, course | RowPlay Studio | Existing native systems |
| Low / failure athlete | RowPlay Studio | Procedural `ReplayAthleteRig` |

RowPlay Studio does **not** author a second segmented human mannequin for
Medium+. The previous native human body nodes were removed from the generator.

## Synchronisation

```bash
python3 script/sync_rowplay_athlete.py \
  --rowplay-repo /path/to/rowplay \
  --expected-commit dba7211bfa94d3f86e60b75921bd5853ec736f55

python3 script/sync_rowplay_athlete.py \
  --rowplay-repo /path/to/rowplay \
  --expected-commit dba7211bfa94d3f86e60b75921bd5853ec736f55 \
  --check
```

Pin and hashes live in:

- `script/sync_rowplay_athlete.py`
- `Sources/RowPlayStudio/Views/Replay3D/ReplayAthleteCatalog.swift`
- `Sources/RowPlayStudio/Resources/Replay3D/rowplay-athlete-v4-source.json`

Provisional pin values:

| Artifact | SHA-256 |
| --- | --- |
| GLB | `a9a215f07bd39d15daa5c45c5bfbbb1788656ad7916fc39f172c5dcc78129963` |
| USDZ | `5591b13c7d58bc4f44194728c1a2fc1c669086232d2f1bd97723672392c50723` |
| Contract | `96acec971c3247120e71af726388420dd89866437c76c3a417ea267481976dba` |

## Quality and Fallback

| Quality / state | Athlete | Equipment / environment |
| --- | --- | --- |
| Low | Existing procedural | Existing procedural |
| Medium / High / Ultra, valid package | Canonical V4 | Native bundled USDA |
| Any required validation failure | Complete procedural | Complete procedural |

Never construct a partial mixed package after failure. Preserve replay time,
play state, speed, camera, orbit, and rival selection across quality changes.

## Movement Alignment

- Native systems remain authoritative for replay clock, seeking, cadence,
  distance/course placement, cameras, effects, equipment, quality, and
  Reduced Motion.
- The V4 sport animation is sampled deterministically from replay phase via
  `ReplayAthletePoseAdapter` (contract `driveEnd` + landmarks).
- No independent animation timer; pause and seek map exactly.
- Live and rival controllers are independent clones.
- Equipment contact uses `ReplayAthleteContactSolver` for palm/sole targets.
- When PR #171 changes movement phases, update contract data and focused adapter
  tests — not the asset loading pipeline.

Provisional USDZ currently exposes one RealityKit scene animation (row cycle
export path). Contract metadata still describes all three sports for mapping;
multi-clip USDZ completeness is expected to improve when #171 regenerates the
native derivative.

## Accepted Phase 11 Visual Limitations

- Limited face, hands, and muscle detail.
- Simplified body shape and clothing.
- Remaining body/equipment interpenetration (`穿模`) unless it breaks contact
  or obscures movement.
- Current stylised low-poly appearance.

## Phase 12 — Premium Athlete and Deformation Upgrade

See `docs/roadmap.md`. Phase 12 improves anatomy, silhouette, skinning,
deformation, clothing, materials, hands, face, and `穿模` while reusing the
Phase 11 sync/load/quality/fallback boundary.

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
