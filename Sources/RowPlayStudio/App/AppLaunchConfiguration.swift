import Foundation
import SwiftUI

/// Launch-only configuration that keeps scripted automation and acceptance
/// runs deterministic.
///
/// Normal launches use cached data and the user's replay-motion preference.
/// `ROWPLAY_AUTOMATION=1` selects demo data, skips background sync, and reduces
/// replay motion for repeatable Computer Use runs.
/// `ROWPLAY_REPLAY_ACCEPTANCE=1` selects the production replay acceptance
/// harness with fixed demo workouts and no preference persistence.
struct AppLaunchConfiguration: Sendable {
    let automationMode: Bool
    let acceptanceMode: Bool
    let acceptanceConfiguration: ReplayAcceptanceConfiguration?

    /// Demo workouts without sync whenever automation or acceptance is active.
    var usesDeterministicDemoData: Bool {
        automationMode || acceptanceMode
    }

    static func fromEnvironment() -> AppLaunchConfiguration {
        from(environment: ProcessInfo.processInfo.environment)
    }

    static func from(environment: [String: String]) -> AppLaunchConfiguration {
        do {
            return try make(from: environment)
        } catch let diagnostic as ReplayAcceptanceConfiguration.Diagnostic {
            fputs("RowPlay acceptance configuration error: \(diagnostic.rawValue)\n", stderr)
            exit(2)
        } catch {
            fputs("RowPlay acceptance configuration error: invalid launch environment\n", stderr)
            exit(2)
        }
    }

    /// Test seam that surfaces parse failures without terminating the process.
    static func make(from environment: [String: String]) throws -> AppLaunchConfiguration {
        let automationMode = environment["ROWPLAY_AUTOMATION"] == "1"
        let acceptanceConfiguration = try ReplayAcceptanceConfiguration.parse(from: environment)
        let acceptanceMode = acceptanceConfiguration != nil
        return AppLaunchConfiguration(
            automationMode: automationMode,
            acceptanceMode: acceptanceMode,
            acceptanceConfiguration: acceptanceConfiguration
        )
    }
}

private struct AutomationModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

private struct AcceptanceModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var automationModeEnabled: Bool {
        get { self[AutomationModeEnvironmentKey.self] }
        set { self[AutomationModeEnvironmentKey.self] = newValue }
    }

    var acceptanceModeEnabled: Bool {
        get { self[AcceptanceModeEnvironmentKey.self] }
        set { self[AcceptanceModeEnvironmentKey.self] = newValue }
    }
}
