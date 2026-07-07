## 2024-07-03 - WorkoutLibrary SwiftUI Computed Property Bottleneck
**Learning:** In SwiftUI, `ObservableObject` computed properties like `filteredWorkouts` and `summary` are evaluated *on every access* during render cycles. When these do O(N) or O(N log N) work (filtering, mapping, sorting large arrays), it severely drops frames.
**Action:** Always memoize/cache expensive derivations in `ObservableObject` classes. Update the cached properties inside the `didSet` observers of the `@Published` source-of-truth properties instead of computing them on the fly.
## 2024-08-01 - Avoid Caching Non-Sendable Formatters
**Learning:** Reverting to `ISO8601DateFormatter` (or `DateFormatter`) guarded by an `NSLock` to optimize `Date().formatted(.iso8601)` introduces Swift 6 strict-concurrency risks because formatters are non-Sendable. The existing `.formatted()` style is already concurrency-safe.
**Action:** Do not propose caching formatters unless there is profiling evidence, a measured bottleneck, strict-concurrency validation, and benchmark proof. Rely on native Swift format styles for concurrency safety.
