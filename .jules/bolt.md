## 2024-07-03 - WorkoutLibrary SwiftUI Computed Property Bottleneck
**Learning:** In SwiftUI, `ObservableObject` computed properties like `filteredWorkouts` and `summary` are evaluated *on every access* during render cycles. When these do O(N) or O(N log N) work (filtering, mapping, sorting large arrays), it severely drops frames.
**Action:** Always memoize/cache expensive derivations in `ObservableObject` classes. Update the cached properties inside the `didSet` observers of the `@Published` source-of-truth properties instead of computing them on the fly.

## 2026-07-11 - Localized date labels in SwiftUI lists
**Learning:** Replacing `Date.FormatStyle` with a shared `DateFormatter` can change the visible date in locales with non-Gregorian defaults and can freeze the component ordering at the locale active during initialization. `Date.FormatStyle` is a value type that preserves localized date-pattern selection.
**Action:** Keep `Date.FormatStyle` for localized SwiftUI date labels. A `static let` value-style configuration with `.locale(.autoupdatingCurrent)` is safe to reuse when needed; only introduce a mutable `DateFormatter` after profiling and with locale-change and concurrency behavior explicitly covered.

## 2024-11-20 - Non-Sendable Formatters in Swift 6
**Learning:** `ISO8601DateFormatter` and `DateFormatter` are not `Sendable` and are not safe for concurrent `string(from:)` / `date(from:)` use. Caching them as bare `static let` (even with `nonisolated(unsafe)`) only silences the compiler; parallel exports can still race on the formatter's mutable internal state.
**Action:** When caching mutable formatters for performance, wrap them in `Mutex` (see `Concept2Mapper.apiDateFormatter` and the `WorkoutExport` CSV formatters) and access via `withLock`. Prefer value-style formatters such as the `Date.ISO8601FormatStyle` values used by TCX export when they can produce the required format without a shared mutable instance or cross-export contention.
