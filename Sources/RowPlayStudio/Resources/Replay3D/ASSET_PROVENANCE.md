# Replay 3D Asset Provenance

## Native equipment and environments

The six Phase 11 equipment and environment USDA assets in this directory are
original, project-generated work. They contain no third-party model, texture,
logo, trademark, download, or network-derived source material. Geometry is
generated deterministically from the standard-library-only script in this
repository. These files intentionally contain **no human anatomy**.

Regenerate the committed USDA resources and golden contract with:

```sh
python3 script/generate_replay_assets.py
```

Verify that committed output and the contract have not drifted with:

```sh
python3 script/generate_replay_assets.py --check
```

The fixed generation seed is `20260721`. The assets intentionally contain no
camera or light prims: the native RealityKit scene remains authoritative for
camera, lighting, course placement, effects, and fallback behaviour.

## Canonical V4 athlete (upstream, provisional)

The production athlete is not authored by RowPlay Studio. It is the canonical
RowPlay V4 athlete owned by upstream PR #171 and synchronised by
`script/sync_rowplay_athlete.py` into:

- `rowplay-athlete-v4.usdz`
- `rowplay-athlete-v4.contract.json`
- `rowplay-athlete-v4-source.json`

Low quality and total package failure continue to use the lightweight
procedural athlete. Premium anatomy and most interpenetration work are Phase 12.
