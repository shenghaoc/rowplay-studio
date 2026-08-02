# Replay Reference Assets

RowPlay Studio consumes the production cross-platform replay reference owned
by RowPlay `main`.  Studio does not independently redesign the athlete, its
mechanics, the grip contracts, or the visual direction — it ports them into
native architecture (RealityKit, SwiftUI Canvas) and owns only the macOS
delivery.

The integration is pinned to the current RowPlay `main` commit recorded in
`Sources/RowPlayStudio/Resources/ReplayReference/rowplay-source.json`.  Every
bundled artifact records its upstream path, SHA-256, and byte count there or
in a sibling manifest, so the whole bundle is reproducible from the pinned
tree.

## Bundle layout

```
Sources/RowPlayStudio/Resources/ReplayReference/
  rowplay-source.json                  pinned commit + artifact hashes + lineage
  athlete/
    rowplay-athlete-v4.usdz            production anatomical athlete (native derivative)
    rowplay-athlete-v4.contract.json   sealed contract: 19 semantic bones + 32 grip
                                       helpers (51 total), 8 material surface roles,
                                       3 sport clips, contacts, rest transforms
    rowplay-athlete-source.json        athlete provenance manifest
  motion/
    rowplay-motion.bin                 sampled base motion: 3 sports x 257 phases x
                                       19 semantic bones x TRS (little-endian f32)
    rowplay-motion-manifest.json       layout, clip durations, drive ends, landmarks
  equipment/
    rowplay-row-equipment.usdz         converted V3 composites (Blender, dev-time)
    rowplay-ski-equipment.usdz
    rowplay-bike-equipment.usdz
    rowplay-*-equipment.contract.json  node/part/material sidecars (USD-safe names)
    rowplay-equipment-manifest.json    package hashes + source GLB hash
  environment/
    environment-manifest.json          texture hashes + provenance pointer
    textures/<family>/...              13 CC0 material families (diffuse/normal/rough)
  parity/                              regenerated web-parity fixtures
```

## Regenerating the bundle

All generation is development-time only; the app performs no runtime
downloads and no runtime asset network access.

```bash
ROWPLAY_MAIN="$(git -C ../rowplay rev-parse origin/main)"

python3 script/sync_rowplay_reference.py \
  --rowplay-repo ../rowplay --expected-commit "$ROWPLAY_MAIN"

"$BLENDER_BIN" --background --python script/convert_rowplay_equipment.py -- \
  --rowplay-repo ../rowplay --expected-commit "$ROWPLAY_MAIN"

node script/export_rowplay_native_parity.mjs \
  --rowplay-repo ../rowplay --commit "$ROWPLAY_MAIN"

python3 script/validate_rowplay_reference.py   # CI-safe committed-bundle gate
```

`sync_rowplay_reference.py --check` verifies the committed bundle against the
pinned tree (requires the sibling checkout); `validate_rowplay_reference.py`
verifies internal consistency from the committed files alone.

## Ownership

| Piece | Owner | Native consumption |
|---|---|---|
| Production anatomical athlete, 51-bone skeleton, clips, landmarks | RowPlay `main` | `ReplayAthleteLibrary` loads the USDZ; `ReplayAthleteMotionTable` drives the 19 semantic bones from `rowplay-motion.bin` — never from `availableAnimations` names |
| Grip channel + digit closure mechanics | RowPlay `handGrip.ts` | Ported to `RowPlayCore` (`ReplayGripGeometry`, `ReplayHandClosure`, sport contracts); solved once at install, cached per frame |
| Equipment dimensions and contacts | RowPlay `rowRig.ts` / `skiEquipment.ts` / `bikeRig.js` / `bikeSaddle.js` | Ported to `RowPlayCore` contracts; authored V3 composites converted to USDZ for High/Ultra |
| Premium venue stories and tiers | RowPlay `renderer3dEnvironment.ts` | Ported natively (`ReplayEnvironment*`), consuming the bundled CC0 maps |
| 2D venue + participant scenes | RowPlay `renderer.ts` | Ported natively (`Replay2D*`) |
| RealityKit integration, macOS delivery | RowPlay Studio | — |

## Athlete integrity gates

A package that fails any gate atomically selects the complete procedural
fallback (never a mixed scene):

1. source manifest parses, pins one 40-hex commit, and hash-matches the
   contract and USDZ;
2. contract declares the exact semantic + helper hierarchy with finite rest
   transforms and all 8 surface roles;
3. the motion table matches the contract's semantic bones, clip names, and
   drive ends, and comes from the same pinned commit;
4. the loaded USDZ skeleton exposes every contract bone exactly once with
   finite transforms.

## Texture provenance

The 13 environment families are Poly Haven CC0-1.0 assets shipped as 512 px
JPEG derivatives; creators and upstream identities are recorded in
`ASSET_PROVENANCE.md` and hash-pinned in `environment-manifest.json`.  The
venues are generic illustrative environments — never a reconstruction of a
real venue, route, weather, or time of day.

## Phase 12 scope

Current RowPlay already ships the production anatomical athlete, so Phase 12
is no longer "replace the mannequin".  It is optional work beyond parity:
native-specific material/shader refinement, remaining deformation polish,
further contact/intersection polish, optional higher-end scene effects, and
future cross-platform athlete version upgrades.
