# Post-parity capture notes (staged app)

Target: `dist/RowPlayStudio.app` (staged by `./script/build_and_run.sh`).
Reference: the pinned RowPlay `main` build (commit in
`ReplayReference/rowplay-source.json`).

## Checks performed in this environment

- Automated: full `swift test` suite including production-athlete
  activation, deterministic/shuffled seek parity, live/rival independence,
  grip closure parity for both hands of all three sports, equipment
  contract parity, motion-graph channel parity at the pin, 2D kinematics
  parity, camera solver behavior, and rig structure tests.
- Staged bundle gates: `build_and_run.sh --verify`, `--automation`,
  `--sign-verify`; reference-bundle presence check inside
  `dist/RowPlayStudio.app/Contents/Resources`.

## Checks NOT performed (recorded honestly)

The full interactive visual matrix — 2D and 3D × RowErg/SkiErg/BikeErg ×
light/dark × Low/Medium/High/Ultra × live-only/past-session rival/
constant-pace rival × Reduced Motion × compact/large windows, plus the
characteristic movement landmarks (catch/drive/finish/recovery, plant/
press/pole-off, quarter-crank points, grip close-ups) and side-by-side
comparison against the pinned RowPlay build — requires a human at the GUI.
None of those frames are claimed here. The PR remains draft until that
matrix is captured and passes.
