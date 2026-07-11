# Phase 8B Design: Articulated Sport Rigs

## Architecture

```
RowPlayCore/Replay/ReplayRigPose.swift
  ReplayAthleteJointPose     — common joint angles (torso, head, arms, legs)
  RowerRigPose               — + seatZ, handleY/Z, oarSweep, oarFeather
  SkiErgRigPose              — + hipCompression, handleHeight, poleTravel
  BikeErgRigPose             — + crankAngle, wheelAngle, pedalPositions
  ReplaySportRigPose         — enum { .rower, .skierg, .bike }
  ReplayRigPoseSolver        — pure solve() function

RowPlayStudio/Views/Replay3D/
  ReplayMeshFactory.swift    — mesh/material helpers (@MainActor)
  ReplayAthleteRig.swift     — articulated body hierarchy (@MainActor)
  ReplayRowerRig.swift       — RowErg rig (@MainActor)
  ReplaySkiErgRig.swift      — SkiErg rig (@MainActor)
  ReplayBikeErgRig.swift     — BikeErg rig (@MainActor)
  ReplaySportRig.swift       — protocol + factory (@MainActor)
```

## Entity Hierarchy

### Shared Athlete Body
```
pelvis
├── torso
│   ├── shoulders
│   │   ├── upperArm-L → forearm-L → hand-L
│   │   └── upperArm-R → forearm-R → hand-R
│   └── head
├── thigh-L → shin-L → foot-L
└── thigh-R → shin-R → foot-R
```

### RowErg Additions
```
hull, deck, stripe, footplate, rail, seat, handle
oar-L (shaft + collar + blade)
oar-R (shaft + collar + blade)
```

### SkiErg Additions
```
post-L, post-R, topBar, cable
handle-L, handle-R
platform
pole-L (shaft + grip + basket)
pole-R (shaft + grip + basket)
boots-L, boots-R
```

### BikeErg Additions
```
wheel-front, wheel-rear (tyre torus + spokes)
frame (downTube, seatTube, topTube, chainStay-L, chainStay-R)
cranks (chainRing + pedal-L + pedal-R)
handlebar (crossbar + grip-L + grip-R)
rider group (contains athlete body)
saddle
```

## Pose Solver Design

The solver translates `ReplayStrokePose` fields into sport-specific joint angles:

### RowErg
- `cos(warpedPhase)` → drive direction (+1 catch, -1 finish)
- Seat slides along rail: `seatZ = base - drive * 0.22 * amplitude`
- Handle moves: `handleY = base + recovery * 0.04`, `handleZ = base - drive * 0.08 * amplitude`
- Oars sweep: `oarSweep = -side * drive * 0.5 * amplitude`
- Oar feather: `oarFeather = side * (recovery * 0.26 - 0.06)`
- Body lean: torso leans forward at catch, opens at finish
- Arms: IK from shoulder to handle position
- Legs: IK from hip to footplate, knee kinks up at catch

### SkiErg
- `cos(warpedPhase)` → swing direction
- Upper body crunch: `crunch = max(0, -swing)`
- Handles: `handleY = base + swing * 0.16 - crunch * 0.16`, `handleZ = base + swing * 0.25`
- Poles: `poleRotation = -swing * 0.9 - 0.1`
- Legs flex with crunch

### BikeErg
- Crank angle = `phase` (continuous)
- Wheel angle = `phase * 2.4` (faster)
- Pedal positions: `pedalY = crankRadius * cos(crankAngle)`, `pedalZ = crankRadius * sin(crankAngle)`
- Legs: IK from hip to pedal position, knee follows
- Rider sway: `sin(phase) * 0.05`

## Mesh Strategy

- Tapered limbs via lathe geometry (proximal to distal radius with belly)
- Hands: palm ellipsoid + 4 capsule fingers + thumb
- Feet: sole box + toe ellipsoid + heel ellipsoid
- Head: cranium + jaw + ears + hair cap
- Wheels: torus (tyre) + crossed box spokes
- All meshes created once in `ReplayMeshFactory`, shared via `MeshResource`

## Reduced Motion

When `reduceMotion` is true, the solver returns a stable neutral pose:
- All joint angles at rest positions
- Seat/handle/crank at neutral positions
- Oars/poles at rest angles
- Participant position still follows replay distance

## Input Sanitization

Every solver input and output is sanitized:
- `finite(v, fallback)` checks for NaN/Infinity
- Phase wrapped to [0, 2π) range
- Amplitude clamped to [0.72, 1.32]
- All joint angles bounded to anatomically plausible ranges
