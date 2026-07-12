import XCTest
@testable import RowPlayStudio

final class ComputerUseAutomationReadinessTests: XCTestCase {

    func testDefaultIsolationConfigIsFull() {
        let config = IsolationConfig(level: .full, automationMode: false)
        XCTAssertEqual(config.level, .full)
        XCTAssertFalse(config.automationMode)
        XCTAssertTrue(config.chartsEnabled)
        XCTAssertTrue(config.replay3DEnabled)
        XCTAssertTrue(config.replayEnabled)
        XCTAssertTrue(config.detailEnabled)
    }

    func testNoChartsLevelDisablesChartsOnly() {
        let config = IsolationConfig(level: .noCharts, automationMode: false)
        XCTAssertFalse(config.chartsEnabled)
        XCTAssertTrue(config.replay3DEnabled)
        XCTAssertTrue(config.replayEnabled)
        XCTAssertTrue(config.detailEnabled)
    }

    func testNoReplay3DDisables3DOnly() {
        let config = IsolationConfig(level: .noReplay3D, automationMode: false)
        XCTAssertTrue(config.chartsEnabled)
        XCTAssertFalse(config.replay3DEnabled)
        XCTAssertTrue(config.replayEnabled)
        XCTAssertTrue(config.detailEnabled)
    }

    func testNoReplayDisablesAllReplay() {
        let config = IsolationConfig(level: .noReplay, automationMode: false)
        XCTAssertTrue(config.chartsEnabled)
        XCTAssertFalse(config.replay3DEnabled)
        XCTAssertFalse(config.replayEnabled)
        XCTAssertTrue(config.detailEnabled)
    }

    func testSidebarOnlyDisablesDetail() {
        let config = IsolationConfig(level: .sidebarOnly, automationMode: false)
        XCTAssertFalse(config.chartsEnabled)
        XCTAssertFalse(config.replay3DEnabled)
        XCTAssertFalse(config.replayEnabled)
        XCTAssertFalse(config.detailEnabled)
    }

    func testMinimalDisablesEverything() {
        let config = IsolationConfig(level: .minimal, automationMode: false)
        XCTAssertFalse(config.chartsEnabled)
        XCTAssertFalse(config.replay3DEnabled)
        XCTAssertFalse(config.replayEnabled)
        XCTAssertFalse(config.detailEnabled)
    }

    func testAutomationModeUsesFullProductionSurface() {
        let config = IsolationConfig(level: .full, automationMode: true)
        XCTAssertTrue(config.automationMode)
        XCTAssertTrue(config.chartsEnabled)
        XCTAssertTrue(config.replay3DEnabled)
        XCTAssertTrue(config.replayEnabled)
        XCTAssertTrue(config.detailEnabled)
    }

    func testEnvironmentConfigurationUsesIsolationLevelAndAutomationMode() {
        let config = IsolationConfig.from(environment: [
            "ROWPLAY_ISOLATION_LEVEL": "no_replay3d",
            "ROWPLAY_AUTOMATION": "1"
        ])

        XCTAssertEqual(config.level, .noReplay3D)
        XCTAssertTrue(config.automationMode)
    }

    func testInvalidEnvironmentIsolationLevelFallsBackToFull() {
        let config = IsolationConfig.from(environment: [
            "ROWPLAY_ISOLATION_LEVEL": "not-a-level",
            "ROWPLAY_AUTOMATION": "true"
        ])

        XCTAssertEqual(config.level, .full)
        XCTAssertFalse(config.automationMode)
    }

    func testLevelRawValuesMatchEnvironmentStrings() {
        XCTAssertEqual(IsolationConfig.Level.full.rawValue, "full")
        XCTAssertEqual(IsolationConfig.Level.noCharts.rawValue, "no_charts")
        XCTAssertEqual(IsolationConfig.Level.noReplay3D.rawValue, "no_replay3d")
        XCTAssertEqual(IsolationConfig.Level.noReplay.rawValue, "no_replay")
        XCTAssertEqual(IsolationConfig.Level.sidebarOnly.rawValue, "sidebar_only")
        XCTAssertEqual(IsolationConfig.Level.minimal.rawValue, "minimal")
    }

    func testAllCasesCount() {
        XCTAssertEqual(IsolationConfig.Level.allCases.count, 6)
    }
}
