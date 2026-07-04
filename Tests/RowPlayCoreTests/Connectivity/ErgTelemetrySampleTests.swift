import XCTest
@testable import RowPlayCore

final class ErgTelemetrySampleTests: XCTestCase {

    func testSampleHasRequiredFields() {
        let sample = ErgTelemetrySample(
            elapsed: 120,
            distance: 2000,
            pace: 125,
            cadence: 26,
            watts: 200
        )

        XCTAssertEqual(sample.elapsed, 120)
        XCTAssertEqual(sample.distance, 2000)
        XCTAssertEqual(sample.pace, 125)
        XCTAssertEqual(sample.cadence, 26)
        XCTAssertEqual(sample.watts, 200)
        XCTAssertNil(sample.heartRate)
    }

    func testSampleWithHeartRate() {
        let sample = ErgTelemetrySample(
            elapsed: 60,
            distance: 1000,
            pace: 130,
            cadence: 24,
            watts: 180,
            heartRate: 155
        )

        XCTAssertEqual(sample.heartRate, 155)
    }

    func testSampleEquality() {
        let date = Date(timeIntervalSince1970: 1000)
        let s1 = ErgTelemetrySample(
            elapsed: 60, distance: 1000, pace: 125,
            cadence: 26, watts: 200, heartRate: 150, timestamp: date
        )
        let s2 = ErgTelemetrySample(
            elapsed: 60, distance: 1000, pace: 125,
            cadence: 26, watts: 200, heartRate: 150, timestamp: date
        )

        XCTAssertEqual(s1, s2)
    }

    func testSampleInequalityDifferentElapsed() {
        let date = Date(timeIntervalSince1970: 1000)
        let s1 = ErgTelemetrySample(
            elapsed: 60, distance: 1000, pace: 125,
            cadence: 26, watts: 200, timestamp: date
        )
        let s2 = ErgTelemetrySample(
            elapsed: 61, distance: 1000, pace: 125,
            cadence: 26, watts: 200, timestamp: date
        )

        XCTAssertNotEqual(s1, s2)
    }

    func testSampleCodable() throws {
        let sample = ErgTelemetrySample(
            elapsed: 120,
            distance: 2000,
            pace: 125.5,
            cadence: 26.5,
            watts: 200,
            heartRate: 155,
            timestamp: Date(timeIntervalSince1970: 1000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(sample)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ErgTelemetrySample.self, from: data)

        XCTAssertEqual(decoded.elapsed, sample.elapsed)
        XCTAssertEqual(decoded.distance, sample.distance)
        XCTAssertEqual(decoded.pace, sample.pace)
        XCTAssertEqual(decoded.cadence, sample.cadence)
        XCTAssertEqual(decoded.watts, sample.watts)
        XCTAssertEqual(decoded.heartRate, sample.heartRate)
    }

    func testSampleTimestampDefaultsToNow() {
        let before = Date()
        let sample = ErgTelemetrySample(
            elapsed: 0, distance: 0, pace: 0, cadence: 0, watts: 0
        )
        let after = Date()

        XCTAssertGreaterThanOrEqual(sample.timestamp, before)
        XCTAssertLessThanOrEqual(sample.timestamp, after)
    }

    func testDeviceEquality() {
        let id = UUID()
        let d1 = ErgDevice(id: id, displayName: "Rower A", sport: .rower, connectionKind: .bluetooth)
        let d2 = ErgDevice(id: id, displayName: "Rower A", sport: .rower, connectionKind: .bluetooth)

        XCTAssertEqual(d1, d2)
    }

    func testDeviceInequalityDifferentID() {
        let d1 = ErgDevice(displayName: "Rower A", sport: .rower)
        let d2 = ErgDevice(displayName: "Rower A", sport: .rower)

        XCTAssertNotEqual(d1, d2)
    }

    func testDeviceCodable() throws {
        let device = ErgDevice(
            id: UUID(uuidString: "12345678-1234-1234-1234-123456789ABC")!,
            displayName: "Test SkiErg",
            manufacturer: "Concept2",
            sport: .skierg,
            connectionKind: .bluetooth
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(device)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ErgDevice.self, from: data)

        XCTAssertEqual(decoded.id, device.id)
        XCTAssertEqual(decoded.displayName, device.displayName)
        XCTAssertEqual(decoded.manufacturer, device.manufacturer)
        XCTAssertEqual(decoded.sport, device.sport)
        XCTAssertEqual(decoded.connectionKind, device.connectionKind)
    }

    func testConnectionStateEquality() {
        XCTAssertEqual(ErgConnectionState.disconnected, ErgConnectionState.disconnected)
        XCTAssertEqual(ErgConnectionState.connected, ErgConnectionState.connected)
        XCTAssertEqual(
            ErgConnectionState.failed(reason: "test"),
            ErgConnectionState.failed(reason: "test")
        )
        XCTAssertNotEqual(
            ErgConnectionState.failed(reason: "a"),
            ErgConnectionState.failed(reason: "b")
        )
    }

    func testConnectionStateIsConnected() {
        XCTAssertFalse(ErgConnectionState.disconnected.isConnected)
        XCTAssertFalse(ErgConnectionState.scanning.isConnected)
        XCTAssertFalse(ErgConnectionState.connecting.isConnected)
        XCTAssertTrue(ErgConnectionState.connected.isConnected)
        XCTAssertFalse(ErgConnectionState.failed(reason: "").isConnected)
    }

    func testConnectionStateIsTerminal() {
        XCTAssertTrue(ErgConnectionState.disconnected.isTerminal)
        XCTAssertFalse(ErgConnectionState.scanning.isTerminal)
        XCTAssertFalse(ErgConnectionState.connecting.isTerminal)
        XCTAssertFalse(ErgConnectionState.connected.isTerminal)
        XCTAssertTrue(ErgConnectionState.failed(reason: "").isTerminal)
    }
}
