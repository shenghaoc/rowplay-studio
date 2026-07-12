import Foundation
import SwiftUI

/// Launch-only configuration that keeps scripted automation deterministic.
///
/// Normal launches use cached data and the user's replay-motion preference.
/// `ROWPLAY_AUTOMATION=1` instead selects demo data, skips background sync, and
/// reduces replay motion for repeatable Computer Use runs.
struct AppLaunchConfiguration: Sendable {
    let automationMode: Bool

    static func fromEnvironment() -> AppLaunchConfiguration {
        from(environment: ProcessInfo.processInfo.environment)
    }

    static func from(environment: [String: String]) -> AppLaunchConfiguration {
        AppLaunchConfiguration(automationMode: environment["ROWPLAY_AUTOMATION"] == "1")
    }
}

private struct AutomationModeEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var automationModeEnabled: Bool {
        get { self[AutomationModeEnvironmentKey.self] }
        set { self[AutomationModeEnvironmentKey.self] = newValue }
    }
}
