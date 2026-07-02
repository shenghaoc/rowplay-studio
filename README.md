# RowPlay Studio

Native macOS port of rowplay, the Concept2 logbook analytics and real-time replay app.

This repository starts as a SwiftPM macOS app with a separate `RowPlayCore` library so the domain model, analytics, replay engine, sync, and storage layers can be reviewed independently from the SwiftUI shell.

## Current Status

Phase 0 is a native bootstrap, not a full product port. It includes:

- SwiftPM package with `RowPlayStudio` app and `RowPlayCore` library targets.
- A macOS `NavigationSplitView` shell with demo workouts, dashboard summaries, charts, workout detail, and split/stroke views.
- Deterministic demo data ported from the web app's sample Concept2 workouts.
- Initial core analytics and formatting tests.
- Codex Run action and CI scaffolding.

## Run

```bash
./script/build_and_run.sh
```

Useful variants:

```bash
./script/build_and_run.sh --verify
./script/build_and_run.sh --logs
./script/build_and_run.sh --telemetry
```

## Validate

```bash
swift test
swift build
```

## Roadmap

The numbered native roadmap lives in [docs/roadmap.md](docs/roadmap.md). Phase 1 and later should land through separate pull requests.

