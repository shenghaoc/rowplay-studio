import XCTest
@testable import RowPlayCore
@testable import RowPlayPlatform
@testable import RowPlayStudio

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "RowPlayStudioTests.AppPreferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultsRepresentExistingSettings() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.demoModeEnabled)
        XCTAssertFalse(preferences.reduceReplayMotion)
        XCTAssertEqual(preferences.distanceUnit, .metric)
    }

    func testLoadsPersistedSettingsFromAllowedKeys() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        defaults.set(true, forKey: AppPreferences.reduceReplayMotionKey)
        defaults.set("imperial", forKey: AppPreferences.preferredDistanceUnitKey)

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.demoModeEnabled)
        XCTAssertTrue(preferences.reduceReplayMotion)
        XCTAssertEqual(preferences.distanceUnit, .imperial)
    }

    func testPreferenceChangesPersistToAllowedKeys() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.demoModeEnabled = false
        preferences.reduceReplayMotion = true
        preferences.distanceUnit = .imperial

        XCTAssertEqual(defaults.object(forKey: AppPreferences.demoModeEnabledKey) as? Bool, false)
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.reduceReplayMotionKey))
        XCTAssertEqual(defaults.string(forKey: AppPreferences.preferredDistanceUnitKey), "imperial")
    }

    func testInvalidDistanceUnitFallsBackToMetric() {
        defaults.set("furlongs", forKey: AppPreferences.preferredDistanceUnitKey)

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.distanceUnit, .metric)
    }

    func testReduceMotionCanBeChangedWithoutChangingOtherDefaults() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.reduceReplayMotion = true

        XCTAssertTrue(preferences.reduceReplayMotion)
        XCTAssertTrue(preferences.demoModeEnabled)
        XCTAssertEqual(preferences.distanceUnit, .metric)
    }
}
