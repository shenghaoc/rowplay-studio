import XCTest
@testable import RowPlayStudio

final class ComputerUseAutomationReadinessTests: XCTestCase {

    func testDefaultLaunchConfigurationDisablesAutomation() throws {
        let config = try AppLaunchConfiguration.make(from: [:])
        XCTAssertFalse(config.automationMode)
        XCTAssertFalse(config.acceptanceMode)
    }

    func testAutomationModeUsesDeterministicLaunchConfiguration() throws {
        let config = try AppLaunchConfiguration.make(from: ["ROWPLAY_AUTOMATION": "1"])
        XCTAssertTrue(config.automationMode)
        XCTAssertFalse(config.acceptanceMode)
    }

    func testAutomationModeRequiresExplicitEnabledValue() throws {
        let config = try AppLaunchConfiguration.make(from: ["ROWPLAY_AUTOMATION": "true"])
        XCTAssertFalse(config.automationMode)
    }

    func testAcceptanceModeIsLaunchOnlyAndDeterministic() throws {
        let config = try AppLaunchConfiguration.make(from: [
            "ROWPLAY_REPLAY_ACCEPTANCE": "1",
            "ROWPLAY_QA_SPORT": "rower"
        ])
        XCTAssertTrue(config.acceptanceMode)
        XCTAssertTrue(config.usesDeterministicDemoData)
        XCTAssertNotNil(config.acceptanceConfiguration)
    }
}
