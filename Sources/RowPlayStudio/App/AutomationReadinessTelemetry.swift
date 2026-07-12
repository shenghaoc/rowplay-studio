import Foundation
import os

/// Emits only launch and app-identity diagnostics needed to separate staged-app
/// failures from Computer Use host failures. It intentionally excludes workout,
/// account, and filesystem data.
enum AutomationReadinessTelemetry {
    private static let logger = Logger(
        subsystem: "com.shenghaoc.RowPlayStudio",
        category: "automation-readiness"
    )

    static func recordApplicationLaunch() {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "missing"
        let bundleName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "missing"
        logger.info(
            "application launched bundleIdentifier=\(bundleIdentifier, privacy: .public) bundleName=\(bundleName, privacy: .public)"
        )
    }

    static func recordContentPresented(for config: IsolationConfig) {
        logger.info(
            "main content presented automation=\(config.automationMode, privacy: .public) isolation=\(config.level.rawValue, privacy: .public)"
        )
    }
}
