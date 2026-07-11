/// Navigation state for the detail column.
///
/// Keeping the route and selection-reset behavior in one value makes the
/// sidebar/replay interaction deterministic and directly testable without a
/// UI-introspection dependency.
struct DetailNavigationState: Equatable {
    enum Route: Hashable {
        case replay(workoutID: Int)
    }

    var path: [Route] = []

    mutating func showReplay(workoutID: Int) {
        path.append(.replay(workoutID: workoutID))
    }

    mutating func resetForSelectionChange() {
        path.removeAll()
    }
}
