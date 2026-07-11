import Foundation
import Synchronization

/// Deterministic mock ergometer connection for testing and UI development.
///
/// Does not require network or Bluetooth. Provides manual `emitSample()` for
/// deterministic test advancement without real async timers.
public final class MockErgConnection: Sendable {
    private struct State: Sendable {
        var connectionState: ErgConnectionState = .disconnected
        var connectedDevice: ErgDevice?
        var sampleContinuation: AsyncStream<ErgTelemetrySample>.Continuation?
        var tick = 0
        var elapsed: TimeInterval = 0
        var distance: Double = 0
        var rng: SeededGenerator
        var connectionAttemptID: UInt64 = 0
        var streamGeneration: UInt64 = 0
    }

    private let state: Mutex<State>
    private let seed: UInt64
    private let connectionDelay: Duration

    public let basePace: TimeInterval
    public let baseCadence: Double
    public let baseWatts: Int
    public let baseHeartRate: Int?

    public init(
        basePace: TimeInterval = 125,
        baseCadence: Double = 26,
        baseWatts: Int = 200,
        baseHeartRate: Int? = 155,
        seed: UInt64 = 42,
        connectionDelay: Duration = .milliseconds(10)
    ) {
        self.basePace = basePace
        self.baseCadence = baseCadence
        self.baseWatts = baseWatts
        self.baseHeartRate = baseHeartRate
        self.seed = seed
        self.connectionDelay = connectionDelay
        self.state = Mutex(State(rng: SeededGenerator(seed: seed)))
    }

    public var currentState: ErgConnectionState {
        state.withLock { $0.connectionState }
    }

    public var connectedDevice: ErgDevice? {
        state.withLock { $0.connectedDevice }
    }

    /// Simulate connecting to a device. Transitions through connecting → connected.
    public func connect(to device: ErgDevice) async throws {
        let attemptID = beginConnectionAttempt(to: device)

        do {
            try await Task.sleep(for: connectionDelay)
            try Task.checkCancellation()
            completeConnectionAttempt(attemptID, device: device)
        } catch {
            cancelConnectionAttempt(attemptID)
            throw error
        }
    }

    /// Disconnect from the current device.
    public func disconnect() async {
        let continuationToFinish = markDisconnectedAndTakeContinuation()
        continuationToFinish?.finish()
    }

    /// Simulate a connection failure with a human-readable reason.
    public func simulateFailure(reason: String) {
        let continuationToFinish = state.withLock { state in
            state.connectionAttemptID += 1
            state.connectionState = .failed(reason: reason)
            state.connectedDevice = nil
            let continuation = state.sampleContinuation
            state.sampleContinuation = nil
            return continuation
        }

        continuationToFinish?.finish()
    }

    /// Emit a deterministic telemetry sample to the stream.
    ///
    /// Returns the emitted sample for assertion convenience.
    @discardableResult
    public func emitSample() -> ErgTelemetrySample {
        let (sample, continuation) = state.withLock { state in
            state.tick += 1
            let segmentDuration: TimeInterval = 1 // 1 second per tick
            state.elapsed += segmentDuration

            // Pace varies ±3 sec/500m
            let paceVariation = Double(Int.random(in: -3 ... 3, using: &state.rng))
            let currentPace = max(1.0, basePace + paceVariation)

            // Distance from pace: d = (segmentDuration / pace) * 500
            let segmentDistance = (segmentDuration / currentPace) * 500
            state.distance += segmentDistance

            // Watts varies ±10
            let wattsVariation = Int.random(in: -10 ... 10, using: &state.rng)
            let currentWatts = max(0, baseWatts + wattsVariation)

            // HR varies ±2 bpm
            let hrVariation = Int.random(in: -2 ... 2, using: &state.rng)
            let currentHR = baseHeartRate.map { max(0, $0 + hrVariation) }
            let currentCadence = max(0, baseCadence + Double(Int.random(in: -1 ... 1, using: &state.rng)))

            let sample = ErgTelemetrySample(
                elapsed: state.elapsed,
                distance: state.distance,
                pace: currentPace,
                cadence: currentCadence,
                watts: currentWatts,
                heartRate: currentHR,
                timestamp: Date(timeIntervalSince1970: state.elapsed)
            )
            return (sample, state.sampleContinuation)
        }

        continuation?.yield(sample)
        return sample
    }

    /// Returns an async stream of telemetry samples.
    ///
    /// Samples are emitted when `emitSample()` is called, not on a timer.
    /// The stream finishes when `disconnect()` is called.
    public func telemetryStream() -> AsyncStream<ErgTelemetrySample> {
        let (stream, continuation) = AsyncStream<ErgTelemetrySample>.makeStream()
        let (previousContinuation, generation) = state.withLock { state in
            let previousContinuation = state.sampleContinuation
            state.streamGeneration += 1
            state.sampleContinuation = continuation
            return (previousContinuation, state.streamGeneration)
        }

        continuation.onTermination = { [weak self] _ in
            self?.clearContinuation(generation: generation)
        }

        previousContinuation?.finish()
        return stream
    }

    /// Reset the mock to its initial state.
    public func reset() {
        let continuationToFinish = state.withLock { state in
            state.connectionAttemptID += 1
            state.connectionState = .disconnected
            state.connectedDevice = nil
            let continuation = state.sampleContinuation
            state.sampleContinuation = nil
            state.tick = 0
            state.elapsed = 0
            state.distance = 0
            state.rng = SeededGenerator(seed: seed)
            return continuation
        }

        continuationToFinish?.finish()
    }

    private func clearContinuation(generation: UInt64) {
        state.withLock {
            if $0.streamGeneration == generation {
                $0.sampleContinuation = nil
            }
        }
    }

    private func beginConnectionAttempt(to device: ErgDevice) -> UInt64 {
        state.withLock {
            $0.connectionAttemptID += 1
            $0.connectionState = .connecting
            $0.connectedDevice = device
            return $0.connectionAttemptID
        }
    }

    private func completeConnectionAttempt(_ attemptID: UInt64, device: ErgDevice) {
        state.withLock {
            if $0.connectionAttemptID == attemptID,
               $0.connectionState == .connecting,
               $0.connectedDevice == device {
                $0.connectionState = .connected
            }
        }
    }

    private func cancelConnectionAttempt(_ attemptID: UInt64) {
        state.withLock {
            if $0.connectionAttemptID == attemptID, $0.connectionState == .connecting {
                $0.connectionState = .disconnected
                $0.connectedDevice = nil
            }
        }
    }

    private func markDisconnectedAndTakeContinuation() -> AsyncStream<ErgTelemetrySample>.Continuation? {
        state.withLock {
            $0.connectionAttemptID += 1
            $0.connectionState = .disconnected
            $0.connectedDevice = nil
            let continuationToFinish = $0.sampleContinuation
            $0.sampleContinuation = nil
            return continuationToFinish
        }
    }
}

// MARK: - ErgConnection Conformance

extension MockErgConnection: ErgConnection {}
