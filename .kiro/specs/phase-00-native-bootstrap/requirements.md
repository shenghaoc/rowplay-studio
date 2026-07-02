# Phase 00 Native Bootstrap Requirements

## Requirement 1: Native Repository Scaffold

The project shall provide a SwiftPM package with a macOS executable app target and a reusable core library target.

Acceptance criteria:

- `RowPlayStudio` builds as an executable product.
- `RowPlayCore` builds as a library product.
- Core models do not import SwiftUI or AppKit.

## Requirement 2: Demo-Backed Native Shell

The app shall open to a native macOS split-view experience backed by deterministic demo workouts.

Acceptance criteria:

- The sidebar lists demo workouts.
- Selecting a workout shows native details, metrics, charts, split rows, and stroke data when available.
- The dashboard can summarize the available demo workouts.

## Requirement 3: Roadmap And Review Boundaries

The repository shall document its own native phase roadmap and distinguish scaffold work from product parity.

Acceptance criteria:

- Phase 0 scope and exit criteria are documented.
- Phase 1 onward are described as separate pull-request slices.
- Bluetooth connectivity is documented as later-phase, not initial scope.

## Requirement 4: Local Validation

The scaffold shall provide repeatable local validation and launch commands.

Acceptance criteria:

- `swift test` runs core tests.
- `swift build` builds the package.
- `script/build_and_run.sh` stages and launches a local `.app` bundle.
- `.codex/environments/environment.toml` exposes a Run action.

