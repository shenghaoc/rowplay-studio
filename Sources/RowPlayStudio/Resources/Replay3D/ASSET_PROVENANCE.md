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

## Canonical V4 athlete (merged upstream handoff)

The production athlete is not authored by RowPlay Studio. It is the canonical
RowPlay V4 athlete from merged upstream PR #171, pinned to merge commit
`da0dc73bf295871e9b362511cd5b2c9a9424b325` and synchronised from that exact
Git tree by `script/sync_rowplay_athlete.py` into:

- `rowplay-athlete-v4.usdz`
- `rowplay-athlete-v4.contract.json`
- `rowplay-athlete-v4-source.json`

The pinned handoff hashes are:

| Artifact | SHA-256 |
| --- | --- |
| GLB | `73e0ece3e6c6de5a7a020a5097b172ca3e0ed8315c27ff604159b144fa90547b` |
| USDZ | `934b0d3af0454f60a84dde76f95b77121919f5ad7cfc366684a670ae5d99658e` |
| Contract | `e9fb56f372ac1ea44ee5ccaf1d00b5a975e1eb4a1a2ee7843ab9e53609fb189d` |

The current exact USDZ is structurally valid, but it exposes neither the
contract's three exact sport clip names nor all three required sport clips.
Studio therefore rejects the entire canonical package atomically instead of
aliasing a clip or choosing an arbitrary first animation. All quality levels
currently use the complete procedural athlete, equipment, and environment
fallback. Once a corrected upstream V4 handoff satisfies the contract, the
same validation boundary will activate the V4 path without weakening that
fallback guarantee.

Premium anatomy and systematic interpenetration reduction remain Phase 12.
