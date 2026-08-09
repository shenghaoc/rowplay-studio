import RowPlayCore

/// Navigation state for the detail column.
///
/// Keeping the route, replay availability policy, and selection-reset behavior
/// in one value makes the sidebar/replay interaction deterministic and directly
/// testable without a UI-introspection dependency.
struct DetailNavigationState: Equatable {
    enum Route: Hashable {
        case replay(workoutID: Int)
    }

    /// Why the Replay command cannot run right now.
    ///
    /// Both the menu item's disabled state and the runtime push consult the
    /// same policy, so the enabled state a user sees always matches what
    /// invoking the command actually does.
    enum ReplayUnavailability: Equatable {
        case libraryLoading
        case noSelection
        case noStrokeData
        case alreadyPresented
    }

    var path: [Route] = []

    var isReplayPresented: Bool { !path.isEmpty }

    mutating func showReplay(workoutID: Int) {
        path.append(.replay(workoutID: workoutID))
    }

    func replayUnavailability(
        for selectedDetail: WorkoutDetail?,
        isLibraryLoading: Bool
    ) -> ReplayUnavailability? {
        if isLibraryLoading { return .libraryLoading }
        if isReplayPresented { return .alreadyPresented }
        guard let selectedDetail else { return .noSelection }
        guard selectedDetail.workout.hasStrokeData else { return .noStrokeData }
        return nil
    }

    /// Pushes the replay route for whichever workout is selected at the moment
    /// the command fires.
    ///
    /// The replay command must not bake a workout ID into UI closures: AppKit
    /// menu and toolbar bridging can keep dispatching an action captured during
    /// an earlier render pass, which replays the previously selected workout.
    /// Callers pass the freshly resolved selection instead. Returns the pushed
    /// route, or nil when ``replayUnavailability(for:isLibraryLoading:)``
    /// reports the command is unavailable.
    @discardableResult
    mutating func showReplay(
        for selectedDetail: WorkoutDetail?,
        isLibraryLoading: Bool
    ) -> Route? {
        guard replayUnavailability(for: selectedDetail, isLibraryLoading: isLibraryLoading) == nil,
              let selectedDetail
        else { return nil }
        showReplay(workoutID: selectedDetail.id)
        return path.last
    }

    mutating func resetForSelectionChange() {
        path.removeAll()
    }
}
