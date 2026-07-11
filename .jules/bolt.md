## 2024-07-03 - WorkoutLibrary SwiftUI Computed Property Bottleneck
**Learning:** In SwiftUI, `ObservableObject` computed properties like `filteredWorkouts` and `summary` are evaluated *on every access* during render cycles. When these do O(N) or O(N log N) work (filtering, mapping, sorting large arrays), it severely drops frames.
**Action:** Always memoize/cache expensive derivations in `ObservableObject` classes. Update the cached properties inside the `didSet` observers of the `@Published` source-of-truth properties instead of computing them on the fly.

## 2026-07-11 - Localized date labels in SwiftUI lists
**Learning:** Replacing `Date.FormatStyle` with a shared `DateFormatter` can change the visible date in locales with non-Gregorian defaults and can freeze the component ordering at the locale active during initialization. `Date.FormatStyle` is a value type that preserves localized date-pattern selection.
**Action:** Keep `Date.FormatStyle` for localized SwiftUI date labels. A `static let` value-style configuration with `.locale(.autoupdatingCurrent)` is safe to reuse when needed; only introduce a mutable `DateFormatter` after profiling and with locale-change and concurrency behavior explicitly covered.
