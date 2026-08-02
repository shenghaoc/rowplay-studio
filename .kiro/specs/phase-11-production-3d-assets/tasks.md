# Phase 11 — Current RowPlay Parity: Tasks

- [x] Pin current RowPlay `main`; verify merged replay layers (#172–#194)
      are ancestors of the pin.
- [x] Reference bundle: `sync_rowplay_reference.py`,
      `convert_rowplay_equipment.py` (Blender), `validate_rowplay_reference.py`,
      `export_rowplay_native_parity.mjs`; remove `sync_rowplay_athlete.py`
      and `generate_replay_assets.py`.
- [x] Sample `rowplay-motion.bin` (3 sports × 257 phases × 19 bones) from the
      pinned GLB clips with a versioned manifest.
- [x] Refactor the athlete pipeline to the live contract (51 joints) and the
      motion table; remove the `availableAnimations` dependency; production
      athlete activates with deterministic seeks and independent live/rival
      instances.
- [x] Port the grip system to RowPlayCore (channel model, digit closure,
      sport contracts) and apply install-time closures to the helper joints.
- [x] Port equipment contracts (rowRig / skiEquipment / bikeRig / bikeSaddle)
      to RowPlayCore; convert the V3 composites to per-sport USDZ packages
      with sidecars; rebuild the three sport rigs to current concepts.
- [x] Replace the 2D timeline placeholder with per-sport venue scenes ported
      from `renderer.ts`.
- [x] Port the three premium venue stories and the quality-tier contract;
      delete the six-file USDA package.
- [x] Port per-sport chase cameras, rival framing pullback, Reduced Motion
      behavior, and the opaque cool rival tint.
- [x] Regenerate parity fixtures from the pin; add motion/grip/equipment/2D
      parity tests plus athlete, rig, environment-tier, camera and fallback
      tests.
- [x] Update kiro spec, roadmap, source map, beta readiness, asset docs and
      provenance; refresh PR #72.
- [ ] Staged-app visual QA matrix against the pinned RowPlay build (both
      renderers × sports × tiers × themes × rival modes × Reduced Motion),
      recorded honestly in docs/visual-qa.
