import SwiftUI

/// The "Replay Workout" action the workout window publishes to the menu bar.
///
/// The command lives in the menu bar (the discoverable home for a keyboard
/// shortcut on macOS) while the selection it acts on lives in `ContentView`,
/// so it travels as a focused scene value. ``run`` deliberately carries no
/// workout ID: it resolves the current selection when invoked, which keeps the
/// menu item, ⇧⌘P, and the detail toolbar button pointed at the workout the
/// user is looking at even when AppKit dispatches an action closure that was
/// captured during an earlier render pass.
struct ReplayCommand: Equatable {
    /// Nil when the command can run.
    var unavailability: DetailNavigationState.ReplayUnavailability?
    var run: () -> Void

    var isEnabled: Bool { unavailability == nil }

    /// Explains what the user must do when replay is unavailable.
    var help: LocalizedStringKey {
        switch unavailability {
        case .none:
            "Replay the selected workout"
        case .libraryLoading:
            "Available once the workout library finishes loading"
        case .noSelection:
            "Select a workout to replay"
        case .noStrokeData:
            "Replay requires stroke data"
        case .alreadyPresented:
            "Replay is already open"
        }
    }

    /// Compares availability only; the action closure is intentionally
    /// identity-free so a re-render that changes nothing user-visible does not
    /// invalidate the menu.
    static func == (lhs: ReplayCommand, rhs: ReplayCommand) -> Bool {
        lhs.unavailability == rhs.unavailability
    }
}

private struct ReplayCommandFocusedValueKey: FocusedValueKey {
    typealias Value = ReplayCommand
}

extension FocusedValues {
    var replayCommand: ReplayCommand? {
        get { self[ReplayCommandFocusedValueKey.self] }
        set { self[ReplayCommandFocusedValueKey.self] = newValue }
    }
}
