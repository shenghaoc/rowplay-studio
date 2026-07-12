import XCTest
@testable import RowPlayStudio

final class ComputerUseAutomationReadinessTests: XCTestCase {

    func testDefaultLaunchConfigurationDisablesAutomation() {
        let config = AppLaunchConfiguration.from(environment: [:])
        XCTAssertFalse(config.automationMode)
    }

    func testAutomationModeUsesDeterministicLaunchConfiguration() {
        let config = AppLaunchConfiguration.from(environment: ["ROWPLAY_AUTOMATION": "1"])
        XCTAssertTrue(config.automationMode)
    }

    func testAutomationModeRequiresExplicitEnabledValue() {
        let config = AppLaunchConfiguration.from(environment: ["ROWPLAY_AUTOMATION": "true"])
        XCTAssertFalse(config.automationMode)
    }
}
