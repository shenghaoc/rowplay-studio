## 2024-07-03 - WorkoutLibrary SwiftUI Computed Property Bottleneck
**Learning:** In SwiftUI, `ObservableObject` computed properties like `filteredWorkouts` and `summary` are evaluated *on every access* during render cycles. When these do O(N) or O(N log N) work (filtering, mapping, sorting large arrays), it severely drops frames.
**Action:** Always memoize/cache expensive derivations in `ObservableObject` classes. Update the cached properties inside the `didSet` observers of the `@Published` source-of-truth properties instead of computing them on the fly.

## 2026-07-11 - Localized date labels in SwiftUI lists
**Learning:** Replacing `Date.FormatStyle` with a shared `DateFormatter` can change the visible date in locales with non-Gregorian defaults and can freeze the component ordering at the locale active during initialization. `Date.FormatStyle` is a value type that preserves localized date-pattern selection.
**Action:** Keep `Date.FormatStyle` for localized SwiftUI date labels (`Text(..., format:)` or per-call `.formatted(...).locale(environmentLocale)`). Do not replace with a shared `DateFormatter` for UI labels. A `static let` FormatStyle — even with `.locale(.autoupdatingCurrent)` — still ignores SwiftUI environment locale overrides; only introduce a mutable `DateFormatter` after profiling and with locale-change and concurrency behavior explicitly covered.

## 2024-11-20 - Non-Sendable Formatters in Swift 6
**Learning:** `ISO8601DateFormatter` and `DateFormatter` are not `Sendable` and are not safe for concurrent `string(from:)` / `date(from:)` use. Caching them as bare `static let` (even with `nonisolated(unsafe)`) only silences the compiler; parallel exports can still race on the formatter's mutable internal state.
**Action:** When caching mutable formatters for performance, wrap them in `Mutex` (see `Concept2Mapper.apiDateFormatter` and the `WorkoutExport` CSV formatters) and access via `withLock`. Prefer value-style formatters such as the `Date.ISO8601FormatStyle` values used by TCX export when they can produce the required format without a shared mutable instance or cross-export contention.

## 2024-11-21 - FormatStyle Allocations in Hot Loops
**Learning:** Using `Date.ISO8601FormatStyle` with `.formatted()` inside hot loops (like generating thousands of TCX trackpoints) implicitly instantiates a new formatter object under the hood for each call. This results in significant memory allocation overhead.
**Action:** For hot loops that do not require localized auto-updating behavior (e.g. strict ISO8601 data serialization), prefer a statically cached `ISO8601DateFormatter`. Ensure it is wrapped in a `Mutex` to prevent concurrent modification issues since formatters are mutable and not Sendable.
## 2024-11-23 - Inline FormatStyles in SwiftUI views
**Learning:** FormatStyle value types used by `.formatted()` / `Text(..., format:)` are intentionally lightweight. Caching them as `static let` (even with `.locale(.autoupdatingCurrent)`) is a premature optimization that breaks localization: a static style does not follow SwiftUI `.environment(\.locale, ...)` overrides, and can lag system locale/calendar changes relative to `Text`'s environment-driven formatting.
**Action:** Prefer inline `Date.FormatStyle` / `Measurement.FormatStyle` / `Duration.UnitsFormatStyle` in SwiftUI views. When a helper needs an explicit locale (e.g. VoiceOver strings built with `.formatted()`), read `@Environment(\.locale)` and apply `.locale(locale)` on a *local* style created in that call — never a view-level `static let`. Reserve static formatter caches for true hot loops that do not need localization (e.g. ISO8601 export), and wrap mutable `DateFormatter` / `ISO8601DateFormatter` in `Mutex`.

## 2026-07-22 - Do not reintroduce static FormatStyle caches in DashboardView
**Learning:** PR #73 reverted static FormatStyle caches across Studio views after review found i18n regressions. A follow-up Bolt task re-proposed the same DashboardView `static let` pattern; that direction remains incorrect.
**Action:** Keep Dashboard PB dates as `Text(..., format:)` (environment-aware). Bind accessibility measurement/duration/date strings to `@Environment(\.locale)` with per-call styles. Do not re-add `private static let …FormatStyle` for SwiftUI UI strings.
## 2024-11-23 - ISO8601DateFormatter allocation in ReplayRivalFactory
**Learning:** `ReplayRivalFactory.sessionDateLabel` instantiated a new `ISO8601DateFormatter` on every call. This was inefficient, especially since generating rivals could happen often in contexts like updating identity caches.
**Action:** When a deterministic, non-localized date string is needed, use a statically cached `ISO8601DateFormatter` wrapped in a `Mutex` to prevent concurrent access issues, rather than instantiating one inline on every call.

## 2024-11-23 - Higher-Order Functions in Hot Paths
**Learning:** Chaining higher-order array methods like `reduce`, `map`, and `filter` creates intermediate array allocations and causes multiple O(N) traversals of the data. When used on large arrays (like workouts) or inside properties evaluated frequently, this impacts performance.
**Action:** Replace chained higher-order functions with a single `for` loop to accumulate values in a single O(N) pass without extra memory allocations.
