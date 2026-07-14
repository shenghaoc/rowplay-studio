import Combine
import XCTest
@testable import RowPlayCore
@testable import RowPlayPlatform

@MainActor
final class AppPreferencesTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "RowPlayStudioTests.AppPreferences.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    func testDefaultsRepresentExistingSettings() {
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertTrue(preferences.demoModeEnabled)
        XCTAssertFalse(preferences.reduceReplayMotion)
        XCTAssertEqual(preferences.distanceUnit, .metric)
        XCTAssertEqual(preferences.replayRenderQuality, .defaultQuality)
    }

    func testLoadsPersistedSettingsFromAllowedKeys() {
        defaults.set(false, forKey: AppPreferences.demoModeEnabledKey)
        defaults.set(true, forKey: AppPreferences.reduceReplayMotionKey)
        defaults.set("imperial", forKey: AppPreferences.preferredDistanceUnitKey)
        defaults.set("high", forKey: AppPreferences.replayRenderQualityKey)

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertFalse(preferences.demoModeEnabled)
        XCTAssertTrue(preferences.reduceReplayMotion)
        XCTAssertEqual(preferences.distanceUnit, .imperial)
        XCTAssertEqual(preferences.replayRenderQuality, .high)
    }

    func testPreferenceChangesPersistToAllowedKeys() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.demoModeEnabled = false
        preferences.reduceReplayMotion = true
        preferences.distanceUnit = .imperial
        preferences.replayRenderQuality = .low

        XCTAssertEqual(defaults.object(forKey: AppPreferences.demoModeEnabledKey) as? Bool, false)
        XCTAssertTrue(defaults.bool(forKey: AppPreferences.reduceReplayMotionKey))
        XCTAssertEqual(defaults.string(forKey: AppPreferences.preferredDistanceUnitKey), "imperial")
        XCTAssertEqual(defaults.string(forKey: AppPreferences.replayRenderQualityKey), "low")
    }

    func testInvalidDistanceUnitFallsBackToMetric() {
        defaults.set("furlongs", forKey: AppPreferences.preferredDistanceUnitKey)

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.distanceUnit, .metric)
    }

    func testEveryReplayRenderQualityPersists() {
        let preferences = AppPreferences(defaults: defaults)

        for quality in ReplayRenderQuality.allCases {
            preferences.replayRenderQuality = quality

            XCTAssertEqual(
                defaults.string(forKey: AppPreferences.replayRenderQualityKey),
                quality.rawValue
            )
        }
    }

    func testUnknownReplayRenderQualityFallsBackToDefault() {
        defaults.set("cinematic", forKey: AppPreferences.replayRenderQualityKey)

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.replayRenderQuality, .defaultQuality)
    }

    func testWrongTypeReplayRenderQualityFallsBackToDefault() {
        defaults.set(42, forKey: AppPreferences.replayRenderQualityKey)

        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.replayRenderQuality, .defaultQuality)
    }

    func testExternalReplayRenderQualityChangeSynchronizes() async {
        let preferences = AppPreferences(defaults: defaults)
        let synchronized = expectation(description: "external replay quality synchronized")
        let cancellable = preferences.$replayRenderQuality
            .dropFirst()
            .filter { $0 == .ultra }
            .sink { _ in synchronized.fulfill() }

        defaults.set(ReplayRenderQuality.ultra.rawValue, forKey: AppPreferences.replayRenderQualityKey)
        NotificationCenter.default.post(
            name: UserDefaults.didChangeNotification,
            object: defaults
        )

        await fulfillment(of: [synchronized], timeout: 1)
        XCTAssertEqual(preferences.replayRenderQuality, .ultra)
        withExtendedLifetime(cancellable) {}
    }

    func testReplayRenderQualityPersistsNoEphemeralSceneState() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.replayRenderQuality = .ultra

        let persistentDomain = defaults.persistentDomain(forName: suiteName) ?? [:]
        XCTAssertEqual(Set(persistentDomain.keys), [AppPreferences.replayRenderQualityKey])
        XCTAssertEqual(
            persistentDomain[AppPreferences.replayRenderQualityKey] as? String,
            ReplayRenderQuality.ultra.rawValue
        )
    }

    func testReduceMotionCanBeChangedWithoutChangingOtherDefaults() {
        let preferences = AppPreferences(defaults: defaults)

        preferences.reduceReplayMotion = true

        XCTAssertTrue(preferences.reduceReplayMotion)
        XCTAssertTrue(preferences.demoModeEnabled)
        XCTAssertEqual(preferences.distanceUnit, .metric)
        XCTAssertEqual(preferences.replayRenderQuality, .defaultQuality)
    }
}
