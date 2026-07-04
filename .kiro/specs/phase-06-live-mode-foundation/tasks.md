# Phase 06 Live Mode Foundation Tasks

- [ ] Create `Sources/RowPlayCore/Live/LivePollingCadence.swift` with interval presets, effective interval, backoff computation, and staleness threshold.
- [ ] Create `Sources/RowPlayCore/Live/LiveModeState.swift` with LiveModeStatus, LiveModeState value type, and state transition methods.
- [ ] Create `Sources/RowPlayCore/Live/LiveSource.swift` with LiveSource protocol and LivePollResult model.
- [ ] Create `Sources/RowPlayCore/Live/MockLiveSource.swift` with deterministic demo workout generation.
- [ ] Create `Sources/RowPlayCore/Live/DemoLiveSampleGenerator.swift` with sequential in-progress sample generation.
- [ ] Create `Sources/RowPlayStudio/Views/LiveModePanelView.swift` with toggle, interval chips, status display, and warning indicator.
- [ ] Update `Sources/RowPlayStudio/Stores/WorkoutLibrary.swift` with liveState property and ingestLiveResult method.
- [ ] Update `Sources/RowPlayStudio/Views/DashboardView.swift` to embed the live mode panel.
- [ ] Create `Tests/RowPlayCoreTests/Live/LiveModeStateTests.swift` covering state transitions, stale detection, and edge cases.
- [ ] Create `Tests/RowPlayCoreTests/Live/LivePollingCadenceTests.swift` covering effective interval, backoff steps, and backoff reset.
- [ ] Create `Tests/RowPlayCoreTests/Live/MockLiveSourceTests.swift` covering poll returns, ID filtering, and sport distribution.
- [ ] Create `Tests/RowPlayCoreTests/Live/DemoLiveSampleGeneratorTests.swift` covering deterministic generation and progression.
- [ ] Create `.kiro/specs/phase-06-live-mode-foundation` spec documents.
- [ ] Update `docs/source-map.md` with Phase 6 mappings.
- [ ] Update `docs/roadmap.md` Phase 6 status.
- [ ] Run `swift test` — all tests pass.
- [ ] Run `swift build` — clean build.
- [ ] Run `git diff --check` — no whitespace errors.
