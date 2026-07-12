import Foundation
import SwiftUI

/// Controls progressive UI isolation for Computer Use crash diagnosis.
///
/// Read once at app launch from `ProcessInfo.processInfo.environment` and
/// injected into the SwiftUI environment so views can conditionally render
/// sections that may trigger accessibility traversal failures in the
/// Computer Use helper.
///
/// See `.kiro/specs/computer-use-automation-readiness/design.md` for the
/// full isolation strategy.
struct IsolationConfig: Sendable {
    /// Progressive isolation levels, ordered from most to least restrictive.
    enum Level: String, Sendable, CaseIterable {
        /// Full production UI. Default for normal launches.
        case full
        /// Disable SwiftUI Charts views only.
        case noCharts = "no_charts"
        /// Disable RealityKit 3D replay only.
        case noReplay3D = "no_replay3d"
        /// Disable all replay surfaces (3D and Canvas).
        case noReplay = "no_replay"
        /// Sidebar only — no detail view content.
        case sidebarOnly = "sidebar_only"
        /// Bare WindowGroup — no NavigationSplitView content.
        case minimal
    }

    /// The active isolation level.
    let level: Level

    /// Whether the app was launched in automation mode.
    /// Automation mode forces demo data, disables background sync, and
    /// reduces nonessential animation.
    let automationMode: Bool

    // MARK: - Convenience

    var chartsEnabled: Bool {
        level == .full || level == .noReplay3D || level == .noReplay
    }

    var replay3DEnabled: Bool {
        level == .full || level == .noCharts
    }

    var replayEnabled: Bool {
        level == .full || level == .noCharts || level == .noReplay3D
    }

    var detailEnabled: Bool {
        level == .full || level == .noCharts || level == .noReplay3D || level == .noReplay
    }

    // MARK: - Environment Key

    struct EnvironmentKey: SwiftUI.EnvironmentKey {
        static let defaultValue = IsolationConfig(level: .full, automationMode: false)
    }
}

extension EnvironmentValues {
    var isolationConfig: IsolationConfig {
        get { self[IsolationConfig.EnvironmentKey.self] }
        set { self[IsolationConfig.EnvironmentKey.self] = newValue }
    }
}

extension IsolationConfig {
    /// Read configuration from the current process environment.
    /// Called once at app launch.
    static func fromEnvironment() -> IsolationConfig {
        from(environment: ProcessInfo.processInfo.environment)
    }

    /// Parses a launch configuration without reading global process state.
    ///
    /// Keeping the parser separate gives the automation launch contract focused,
    /// deterministic test coverage without exposing launch-only configuration to
    /// the Core or Platform layers.
    static func from(environment: [String: String]) -> IsolationConfig {
        let level: Level = {
            guard let raw = environment["ROWPLAY_ISOLATION_LEVEL"], !raw.isEmpty else {
                return .full
            }
            return Level(rawValue: raw) ?? .full
        }()

        return IsolationConfig(
            level: level,
            automationMode: environment["ROWPLAY_AUTOMATION"] == "1"
        )
    }
}
