# UI Redesign and Design System Tasks

## Spec and Product Narrative

- [x] Add requirements, design, and tasks for the final redesign scope.
- [x] Define the PM5-inspired product and semantic design language.
- [x] Keep the supported product target explicitly macOS-only.

## Design System

- [x] Add adaptive semantic colors, spacing, radii, typography, and chart sizing.
- [x] Add a reusable panel style and remove repeated chart-panel styling.
- [x] Apply tokens across dashboard, sidebar, detail, replay, live mode, settings, and workout tools.

## UX and Accessibility

- [x] Build a stable, representative loading skeleton.
- [x] Add an actionable empty state with Reduce Motion support.
- [x] Keep native toolbar, menu, disclosure, settings, file, alert, and confirmation patterns.
- [x] Expand workout tools by default only in deterministic automation mode for full-flow inspection.
- [x] Add explicit accessibility labels/values to metric groups and chart summaries.
- [x] Distinguish warning, success, and error states semantically.

## Workout Analysis and Performance

- [x] Separate pace and power charts and retain split boundaries.
- [x] Respect metric/imperial units in chart data and labels.
- [x] Cache chart derivations on workout/revision/unit identity changes.
- [x] Downsample charts to at most 500 points while preserving endpoints.
- [x] Extract chart state/rendering into `WorkoutStrokeAnalysisView`.
- [x] Keep dashboard chart/accessibility derivations current when filters or units change.
- [x] Make the comparison pace overlay unit-aware, bounded, faster-is-higher, and explicitly accessible.
- [x] Keep the primary pace ribbon legible at the minimum window while preserving `/500m` semantics.

## Repeated Operations

- [x] Expose library loading state from `Concept2SyncController`.
- [x] Reject overlapping load/sync operations.
- [x] Disable reload, sync, and disconnect actions while loading.
- [x] Add regression coverage for overlapping cache loads.

## Review Feedback

- [x] Use alert red for live polling errors.
- [x] Render all major dashboard sections in the loading skeleton.
- [x] Restore pace formatting and imperial chart units.
- [x] Preserve duplicate split boundaries by position.
- [x] Respect Reduce Motion and add native button styling/legends.
- [x] Remove unused design-system components and centralize panel styling.
- [x] Bound derived power before integer conversion and add regression coverage.
- [x] Refresh replay path and sport color when the selected workout changes in-place.
- [x] Consolidate replay path initialization with `onChange(of:initial:)`.
- [x] Correct the Live Mode SF Symbol name.
- [x] Verify the enumerated split-boundary identity compiles on the Swift 6.3 baseline.

## Documentation and Evidence

- [x] Synchronize `DESIGN.md`, `.impeccable/design.json`, and `PRODUCT.md` with the implementation.
- [x] Replace stale design QA paths with current-run screenshots and notes.
- [x] Update PR title/body, exact validation, and known gaps.

## Final Validation

- [x] Focused Platform overlap regression test.
- [x] Focused workout-chart regression tests.
- [x] `swift test`.
- [x] `swift build`.
- [x] `git diff --check`.
- [x] `./script/build_and_run.sh --verify`.
- [x] Fresh staged-app UX/HIG inspection.
- [x] Final live GitHub checks, review-thread state, and mergeability recheck.
