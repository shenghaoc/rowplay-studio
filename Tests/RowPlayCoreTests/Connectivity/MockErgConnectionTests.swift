import XCTest
@testable import RowPlayCore

final class MockErgConnectionTests: XCTestCase {
    private static let inFlightConnectionDelay: Duration = .milliseconds(250)

    // MARK: - Connection State Transitions

    func testStartsDisconnected() {
        let connection = MockErgConnection()
        XCTAssertEqual(connection.currentState, .disconnected)
        XCTAssertNil(connection.connectedDevice)
    }

    func testConnectTransitionsToConnected() async throws {
        let connection = MockErgConnection()
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        try await connection.connect(to: device)

        XCTAssertEqual(connection.currentState, .connected)
        XCTAssertEqual(connection.connectedDevice, device)
    }

    func testDisconnectTransitionsToDisconnected() async throws {
        let connection = MockErgConnection()
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        try await connection.connect(to: device)
        await connection.disconnect()

        XCTAssertEqual(connection.currentState, .disconnected)
        XCTAssertNil(connection.connectedDevice)
    }

    func testDisconnectDuringInFlightConnectDoesNotBecomeConnected() async throws {
        let connection = MockErgConnection(connectionDelay: Self.inFlightConnectionDelay)
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        let connectTask = Task {
            try await connection.connect(to: device)
        }
        try await waitForState(.connecting, in: connection)

        await connection.disconnect()
        try await connectTask.value

        XCTAssertEqual(connection.currentState, .disconnected)
        XCTAssertNil(connection.connectedDevice)
    }

    func testConnectCancellationCleansUpState() async throws {
        let connection = MockErgConnection(connectionDelay: Self.inFlightConnectionDelay)
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        let connectTask = Task {
            try await connection.connect(to: device)
        }
        try await waitForState(.connecting, in: connection)

        connectTask.cancel()

        do {
            try await connectTask.value
            XCTFail("Cancelled connection should throw CancellationError")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Cancelled connection threw unexpected error: \(error)")
        }

        XCTAssertEqual(connection.currentState, .disconnected)
        XCTAssertNil(connection.connectedDevice)
    }

    func testSimulateFailurePreservesReason() {
        let connection = MockErgConnection()
        connection.simulateFailure(reason: "Device out of range")

        XCTAssertEqual(connection.currentState, .failed(reason: "Device out of range"))
    }

    func testFailureDuringInFlightConnectDoesNotBecomeConnected() async throws {
        let connection = MockErgConnection(connectionDelay: Self.inFlightConnectionDelay)
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        let connectTask = Task {
            try await connection.connect(to: device)
        }
        try await waitForState(.connecting, in: connection)

        connection.simulateFailure(reason: "Signal lost")
        try await connectTask.value

        XCTAssertEqual(connection.currentState, .failed(reason: "Signal lost"))
        XCTAssertNil(connection.connectedDevice)
    }

    func testFailureFinishesTelemetryStreamAndClearsDevice() async throws {
        let connection = MockErgConnection()
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        try await connection.connect(to: device)
        let stream = connection.telemetryStream()

        connection.simulateFailure(reason: "Signal lost")
        let valueAfterFailure = try await nextSample(from: stream)

        XCTAssertNil(valueAfterFailure)
        XCTAssertEqual(connection.currentState, .failed(reason: "Signal lost"))
        XCTAssertNil(connection.connectedDevice)
    }

    func testConnectThenFailureThenConnect() async throws {
        let connection = MockErgConnection()
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        try await connection.connect(to: device)
        connection.simulateFailure(reason: "Signal lost")
        XCTAssertEqual(connection.currentState, .failed(reason: "Signal lost"))

        // Can reconnect after failure
        try await connection.connect(to: device)
        XCTAssertEqual(connection.currentState, .connected)
    }

    // MARK: - Deterministic Telemetry

    func testEmitSampleReturnsSample() async throws {
        let connection = MockErgConnection()
        let sample = connection.emitSample()

        XCTAssertGreaterThan(sample.elapsed, 0)
        XCTAssertGreaterThan(sample.distance, 0)
        XCTAssertGreaterThan(sample.pace, 0)
        XCTAssertGreaterThan(sample.cadence, 0)
        XCTAssertGreaterThan(sample.watts, 0)
    }

    func testElapsedTimeIncreases() {
        let connection = MockErgConnection()
        let s1 = connection.emitSample()
        let s2 = connection.emitSample()
        let s3 = connection.emitSample()

        XCTAssertLessThan(s1.elapsed, s2.elapsed)
        XCTAssertLessThan(s2.elapsed, s3.elapsed)
    }

    func testDistanceDoesNotGoBackward() {
        let connection = MockErgConnection()
        var previousDistance: Double = 0

        for _ in 0 ..< 50 {
            let sample = connection.emitSample()
            XCTAssertGreaterThanOrEqual(sample.distance, previousDistance)
            previousDistance = sample.distance
        }
    }

    func testNonPositiveBasePaceIsClamped() {
        let connection = MockErgConnection(basePace: -3)
        var previousDistance: Double = 0

        for _ in 0 ..< 10 {
            let sample = connection.emitSample()
            XCTAssertGreaterThanOrEqual(sample.pace, 1)
            XCTAssertTrue(sample.distance.isFinite)
            XCTAssertGreaterThanOrEqual(sample.distance, previousDistance)
            previousDistance = sample.distance
        }
    }

    func testTelemetryContainsCadenceAndWatts() {
        let connection = MockErgConnection()
        let sample = connection.emitSample()

        // Cadence should be within reasonable range of base
        XCTAssertGreaterThan(sample.cadence, 0)
        // Watts should be within reasonable range of base
        XCTAssertGreaterThan(sample.watts, 0)
    }

    func testTelemetryClampsNonNegativeValues() {
        let connection = MockErgConnection(baseCadence: -5, baseWatts: -5, baseHeartRate: -1)

        for _ in 0 ..< 10 {
            let sample = connection.emitSample()
            XCTAssertGreaterThanOrEqual(sample.cadence, 0)
            XCTAssertGreaterThanOrEqual(sample.watts, 0)
            XCTAssertGreaterThanOrEqual(sample.heartRate ?? 0, 0)
        }
    }

    func testTelemetryIsDeterministic() {
        let c1 = MockErgConnection(seed: 99)
        let c2 = MockErgConnection(seed: 99)

        let s1 = c1.emitSample()
        let s2 = c2.emitSample()

        XCTAssertEqual(s1.elapsed, s2.elapsed)
        XCTAssertEqual(s1.distance, s2.distance)
        XCTAssertEqual(s1.pace, s2.pace)
        XCTAssertEqual(s1.cadence, s2.cadence)
        XCTAssertEqual(s1.watts, s2.watts)
        XCTAssertEqual(s1.heartRate, s2.heartRate)
        XCTAssertEqual(s1.timestamp, s2.timestamp)
    }

    func testReplacingTelemetryStreamFinishesPreviousStream() async throws {
        let connection = MockErgConnection()
        let firstStream = connection.telemetryStream()
        let secondStream = connection.telemetryStream()

        let firstValue = try await nextSample(from: firstStream)
        XCTAssertNil(firstValue)

        let emitted = connection.emitSample()
        let secondValue = try await nextSample(from: secondStream)

        XCTAssertEqual(secondValue?.elapsed, emitted.elapsed)
        XCTAssertEqual(secondValue?.distance, emitted.distance)
        XCTAssertEqual(secondValue?.pace, emitted.pace)
        XCTAssertEqual(secondValue?.cadence, emitted.cadence)
        XCTAssertEqual(secondValue?.watts, emitted.watts)
        XCTAssertEqual(secondValue?.heartRate, emitted.heartRate)
    }

    func testHeartRateIsIncluded() {
        let connection = MockErgConnection(baseHeartRate: 160)
        let sample = connection.emitSample()

        XCTAssertNotNil(sample.heartRate)
        // HR should be within reasonable range of base
        if let hr = sample.heartRate {
            XCTAssertGreaterThan(hr, 150)
            XCTAssertLessThan(hr, 170)
        }
    }

    func testHeartRateCanBeNil() {
        let connection = MockErgConnection(baseHeartRate: nil)
        let sample = connection.emitSample()

        XCTAssertNil(sample.heartRate)
    }

    func testResetReturnsToInitialState() async throws {
        let connection = MockErgConnection()
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        try await connection.connect(to: device)
        connection.emitSample()
        connection.emitSample()

        connection.reset()

        XCTAssertEqual(connection.currentState, .disconnected)
        XCTAssertNil(connection.connectedDevice)

        // After reset, first sample elapsed should be same as fresh connection
        let fresh = MockErgConnection()
        let s1 = connection.emitSample()
        let s2 = fresh.emitSample()
        XCTAssertEqual(s1.elapsed, s2.elapsed)
    }

    func testResetRestoresCustomSeedSequence() {
        let connection = MockErgConnection(seed: 99)
        let first = connection.emitSample()
        _ = connection.emitSample()

        connection.reset()

        let afterReset = connection.emitSample()
        XCTAssertEqual(afterReset.elapsed, first.elapsed)
        XCTAssertEqual(afterReset.distance, first.distance)
        XCTAssertEqual(afterReset.pace, first.pace)
        XCTAssertEqual(afterReset.cadence, first.cadence)
        XCTAssertEqual(afterReset.watts, first.watts)
        XCTAssertEqual(afterReset.heartRate, first.heartRate)
        XCTAssertEqual(afterReset.timestamp, first.timestamp)
    }

    func testFailureStateIsTerminal() {
        let connection = MockErgConnection()
        connection.simulateFailure(reason: "Battery low")

        XCTAssertTrue(connection.currentState.isTerminal)
        XCTAssertFalse(connection.currentState.isConnected)
    }

    func testDisconnectedStateIsTerminal() {
        let connection = MockErgConnection()

        XCTAssertTrue(connection.currentState.isTerminal)
        XCTAssertFalse(connection.currentState.isConnected)
    }

    func testConnectedStateIsNotTerminal() async throws {
        let connection = MockErgConnection()
        let device = ErgDevice(displayName: "Test Rower", sport: .rower)

        try await connection.connect(to: device)

        XCTAssertFalse(connection.currentState.isTerminal)
        XCTAssertTrue(connection.currentState.isConnected)
    }

    private enum AsyncTestError: Error {
        case timedOut
    }

    private func waitForState(_ state: ErgConnectionState, in connection: MockErgConnection) async throws {
        for _ in 0 ..< 500 {
            if connection.currentState == state {
                return
            }
            try await Task.sleep(for: .milliseconds(1))
        }
        throw AsyncTestError.timedOut
    }

    private func nextSample(
        from stream: AsyncStream<ErgTelemetrySample>,
        timeoutNanoseconds: UInt64 = 500_000_000
    ) async throws -> ErgTelemetrySample? {
        try await withThrowingTaskGroup(of: ErgTelemetrySample?.self) { group -> ErgTelemetrySample? in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try await Task.sleep(for: .nanoseconds(Int64(timeoutNanoseconds)))
                throw AsyncTestError.timedOut
            }

            guard let result = try await group.next() else {
                throw AsyncTestError.timedOut
            }
            group.cancelAll()
            return result
        }
    }
}
