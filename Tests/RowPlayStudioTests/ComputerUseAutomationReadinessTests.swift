import XCTest
@testable import RowPlayStudio

final class ComputerUseAutomationReadinessTests: XCTestCase {

    // MARK: - IsolationConfig Defaults

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

    // MARK: - Automation Mode

    func testAutomationModeFlag() {
        let config = IsolationConfig(level: .full, automationMode: true)
        XCTAssertTrue(config.automationMode)
        // Automation mode uses full production UI
        XCTAssertTrue(config.chartsEnabled)
        XCTAssertTrue(config.replay3DEnabled)
        XCTAssertTrue(config.replayEnabled)
        XCTAssertTrue(config.detailEnabled)
    }

    // MARK: - Level Raw Values

    func testLevelRawValuesMatchEnvironmentStrings() {
        XCTAssertEqual(IsolationConfig.Level.full.rawValue, "full")
        XCTAssertEqual(IsolationConfig.Level.noCharts.rawValue, "no_charts")
        XCTAssertEqual(IsolationConfig.Level.noReplay3D.rawValue, "no_replay3d")
        XCTAssertEqual(IsolationConfig.Level.noReplay.rawValue, "no_replay")
        XCTAssertEqual(IsolationConfig.Level.sidebarOnly.rawValue, "sidebar_only")
        XCTAssertEqual(IsolationConfig.Level.minimal.rawValue, "minimal")
    }

    func testLevelInitFromInvalidRawValueReturnsNil() {
        XCTAssertNil(IsolationConfig.Level(rawValue: "invalid"))
        XCTAssertNil(IsolationConfig.Level(rawValue: ""))
    }

    // MARK: - All Cases

    func testAllCasesCount() {
        XCTAssertEqual(IsolationConfig.Level.allCases.count, 6)
    }
}
