import XCTest
@testable import RowPlayStudio
import RowPlayCore

final class ReplayAcceptanceConfigurationTests: XCTestCase {

    func testDefaultLaunchRemainsUnchanged() throws {
        let config = try AppLaunchConfiguration.make(from: [:])
        XCTAssertFalse(config.automationMode)
        XCTAssertFalse(config.acceptanceMode)
        XCTAssertNil(config.acceptanceConfiguration)
        XCTAssertFalse(config.usesDeterministicDemoData)
    }

    func testAutomationModeUnchangedWhenAcceptanceInactive() throws {
        let config = try AppLaunchConfiguration.make(from: ["ROWPLAY_AUTOMATION": "1"])
        XCTAssertTrue(config.automationMode)
        XCTAssertFalse(config.acceptanceMode)
        XCTAssertTrue(config.usesDeterministicDemoData)
    }

    func testAcceptanceRequiresExplicitFlag() throws {
        let config = try AppLaunchConfiguration.make(from: [
            "ROWPLAY_QA_SPORT": "rower"
        ])
        XCTAssertFalse(config.acceptanceMode)
        XCTAssertNil(config.acceptanceConfiguration)
    }

    func testValidEnvironmentValues() throws {
        let env: [String: String] = [
            "ROWPLAY_REPLAY_ACCEPTANCE": "1",
            "ROWPLAY_QA_SPORT": "skierg",
            "ROWPLAY_QA_RENDERER": "2d",
            "ROWPLAY_QA_QUALITY": "ultra",
            "ROWPLAY_QA_CAMERA": "orbit",
            "ROWPLAY_QA_THEME": "light",
            "ROWPLAY_QA_RIVAL": "session",
            "ROWPLAY_QA_TIME": "12.5",
            "ROWPLAY_QA_REDUCED_MOTION": "1",
            "ROWPLAY_QA_WIDTH": "1000",
            "ROWPLAY_QA_HEIGHT": "700",
            "ROWPLAY_QA_OUTPUT": "/tmp/rowplay-acceptance-test"
        ]
        let config = try AppLaunchConfiguration.make(from: env)
        XCTAssertTrue(config.acceptanceMode)
        XCTAssertTrue(config.usesDeterministicDemoData)
        let acceptance = try XCTUnwrap(config.acceptanceConfiguration)
        XCTAssertEqual(acceptance.sport, .skierg)
        XCTAssertEqual(acceptance.rendererMode, .twoD)
        XCTAssertEqual(acceptance.quality, .ultra)
        XCTAssertEqual(acceptance.camera, .orbit)
        XCTAssertEqual(acceptance.theme, .light)
        XCTAssertEqual(acceptance.rival, .session)
        XCTAssertEqual(acceptance.timeSeconds, 12.5)
        XCTAssertTrue(acceptance.reducedMotion)
        XCTAssertEqual(acceptance.windowWidth, 1000)
        XCTAssertEqual(acceptance.windowHeight, 700)
        XCTAssertEqual(acceptance.outputDirectory, "/tmp/rowplay-acceptance-test")
        XCTAssertEqual(acceptance.demoWorkoutID, ReplayAcceptanceConfiguration.skiergDemoWorkoutID)
    }

    func testSportDemoWorkoutMapping() {
        XCTAssertEqual(
            ReplayAcceptanceConfiguration.demoWorkoutID(for: .rower),
            1001
        )
        XCTAssertEqual(
            ReplayAcceptanceConfiguration.demoWorkoutID(for: .skierg),
            1003
        )
        XCTAssertEqual(
            ReplayAcceptanceConfiguration.demoWorkoutID(for: .bike),
            1004
        )
    }

    func testInvalidValuesFailDeterministically() {
        let cases: [(String, String, ReplayAcceptanceConfiguration.Diagnostic)] = [
            ("ROWPLAY_QA_SPORT", "swim", .invalidSport),
            ("ROWPLAY_QA_RENDERER", "metal", .invalidRenderer),
            ("ROWPLAY_QA_QUALITY", "max", .invalidQuality),
            ("ROWPLAY_QA_CAMERA", "firstperson", .invalidCamera),
            ("ROWPLAY_QA_THEME", "solarized", .invalidTheme),
            ("ROWPLAY_QA_RIVAL", "ghost", .invalidRival),
            ("ROWPLAY_QA_TIME", "-1", .invalidTime),
            ("ROWPLAY_QA_TIME", "nan", .invalidTime),
            ("ROWPLAY_QA_REDUCED_MOTION", "yes", .invalidReducedMotion),
            ("ROWPLAY_QA_WIDTH", "100", .invalidWidth),
            ("ROWPLAY_QA_HEIGHT", "99999", .invalidHeight),
            ("ROWPLAY_QA_OUTPUT", "   ", .invalidOutput),
        ]

        for (key, value, expected) in cases {
            var env = baseAcceptanceEnvironment()
            env[key] = value
            XCTAssertThrowsError(try AppLaunchConfiguration.make(from: env), "expected failure for \(key)=\(value)") { error in
                XCTAssertEqual(error as? ReplayAcceptanceConfiguration.Diagnostic, expected)
            }
        }
    }

    func testAcceptanceForcesDemoWithoutPersistenceFlag() throws {
        let config = try AppLaunchConfiguration.make(from: baseAcceptanceEnvironment())
        let acceptance = try XCTUnwrap(config.acceptanceConfiguration)
        let viewConfig = acceptance.makeViewConfiguration()
        XCTAssertFalse(viewConfig.persistsQualityPreference)
        XCTAssertEqual(viewConfig.quality, .medium)
        XCTAssertEqual(viewConfig.rendererMode, .threeD)
    }

    func testConfigurationIsSendableAndFinite() throws {
        let config = try XCTUnwrap(
            try ReplayAcceptanceConfiguration.parse(from: baseAcceptanceEnvironment())
        )
        XCTAssertTrue(config.timeSeconds.isFinite)
        XCTAssertTrue(config.windowWidth.isFinite)
        XCTAssertTrue(config.windowHeight.isFinite)
        let boxed: any Sendable = config
        XCTAssertNotNil(boxed)
    }

    private func baseAcceptanceEnvironment() -> [String: String] {
        [
            "ROWPLAY_REPLAY_ACCEPTANCE": "1",
            "ROWPLAY_QA_SPORT": "rower",
            "ROWPLAY_QA_RENDERER": "3d",
            "ROWPLAY_QA_QUALITY": "medium",
            "ROWPLAY_QA_CAMERA": "chase",
            "ROWPLAY_QA_THEME": "dark",
            "ROWPLAY_QA_RIVAL": "none",
            "ROWPLAY_QA_TIME": "10",
            "ROWPLAY_QA_REDUCED_MOTION": "0",
            "ROWPLAY_QA_WIDTH": "1280",
            "ROWPLAY_QA_HEIGHT": "800"
        ]
    }
}
