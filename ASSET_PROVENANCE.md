# Asset Provenance

Every visual asset RowPlay Studio ships is either authored inside the RowPlay
repositories or a CC0 material map with recorded provenance.  No downloaded
human model, third-party character, scan, likeness, avatar generator output,
or user image contributes to any shipped asset.

## Production athlete

- Owner: RowPlay `main` (upstream repository
  `https://github.com/shenghaoc/rowplay`).
- Source: repository-authored Blender 5 parametric athlete derived from the
  Blender Foundation Human Base Meshes bundle v1.4.1 (CC0), rebuilt entirely
  by `scripts/build-replay-athlete-v4-blender.py` in the upstream tree.
- Licence: MIT (upstream repository licence); base mesh CC0.
- Shipped artifacts: `ReplayReference/athlete/rowplay-athlete-v4.usdz`
  (upstream-built native derivative) and its sealed contract.  Hashes and the
  pinned upstream commit are recorded in
  `ReplayReference/athlete/rowplay-athlete-source.json` and
  `ReplayReference/rowplay-source.json`.

## Motion table

- `ReplayReference/motion/rowplay-motion.bin` is sampled at development time
  from the upstream athlete GLB's three authored sport clips by
  `script/sync_rowplay_reference.py`.  The manifest records the source commit
  and GLB hash.  No motion capture and no user telemetry contribute.

## Equipment packages

- Source: upstream `static/replay-assets/rowplay-rigs-v3.glb`
  (repository-authored composites; the BikeErg source lineage is documented
  upstream in `static/replay-assets/source/bike/PROVENANCE.md`).
- Converted to per-sport USDZ by `script/convert_rowplay_equipment.py`
  (Blender, development time).  Names, transforms and bounds are preserved;
  no geometry is redesigned.  Hashes in
  `ReplayReference/equipment/rowplay-equipment-manifest.json`.

## Environment material maps

13 texture families under `ReplayReference/environment/textures/`, shipped as
512 px JPEG derivatives.  All are Poly Haven assets under CC0 1.0
(`https://creativecommons.org/publicdomain/zero/1.0/`); upstream retrieval,
original checksums, and the shipped-file hashes are documented in the pinned
RowPlay tree (`static/replay-assets/environments/README.md`) and re-pinned in
`ReplayReference/environment/environment-manifest.json`.

| Family | Creator | Poly Haven asset |
|---|---|---|
| aerial-grass-rock | Rob Tuytel | `aerial_grass_rock` |
| bark-brown-01 | Rob Tuytel | `bark_brown_01` |
| brown-planks-03 | Rob Tuytel | `brown_planks_03` |
| brushed-concrete-2 | Dimitrios Savva / Dario Barresi | `brushed_concrete_2` |
| cobblestone-floor-03 | Rob Tuytel | `cobblestone_floor_03` |
| concrete-floor-painted | Rob Tuytel | `concrete_floor_painted` |
| dry-river-pebbles | Amal Kumar | `dry_river_pebbles` |
| forest-leaves-04 | Rob Tuytel | `forest_leaves_04` |
| forrest-ground-01 | Rob Tuytel | `forrest_ground_01` |
| leafy-grass | Charlotte Baglioni | `leafy_grass` |
| rock-01 | Rob Tuytel | `rock_01` |
| snow-02 | Rob Tuytel | `snow_02` |
| wood-floor | Dimitrios Savva | `wood_floor` |

The rendered venues are generic illustrative environments.  They never
reconstruct a real venue, route, weather, or time of day — Concept2 workout
data carries no geography.
