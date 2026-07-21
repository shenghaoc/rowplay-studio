# Replay 3D Asset Provenance

The six Phase 11 replay assets in this directory are original, project-generated
work. They contain no third-party model, texture, logo, trademark, download, or
network-derived source material. Their geometry is generated deterministically
from the standard-library-only script in this repository.

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
