## 2024-07-03 - WorkoutLibrary SwiftUI Computed Property Bottleneck
**Learning:** In SwiftUI, `ObservableObject` computed properties like `filteredWorkouts` and `summary` are evaluated *on every access* during render cycles. When these do O(N) or O(N log N) work (filtering, mapping, sorting large arrays), it severely drops frames.
**Action:** Always memoize/cache expensive derivations in `ObservableObject` classes. Update the cached properties inside the `didSet` observers of the `@Published` source-of-truth properties instead of computing them on the fly.

## 2026-07-11 - Caching DateFormatter for SwiftUI view performance
**Learning:** In SwiftUI, `Date.formatted(...)` implicitly creates a new formatting instance on every call. Doing this inside a list loop (like `ForEach` in a `Picker`) can cause significant overhead and drop frames, as the string formatting object is recreated for each item during the view's evaluation.
**Action:** Use a `static let DateFormatter` explicitly configured with `setLocalizedDateFormatFromTemplate` instead of using the inline `.formatted` extensions inside computed properties accessed during list rendering. Set `formatter.locale = .autoupdatingCurrent` so the cached formatter adapts if the user changes their system locale at runtime.
