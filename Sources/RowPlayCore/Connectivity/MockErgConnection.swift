import Foundation

/// Deterministic mock ergometer connection for testing and UI development.
///
/// Does not require network or Bluetooth. Provides manual `emitSample()` for
/// deterministic test advancement without real async timers.
public final class MockErgConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: ErgConnectionState = .disconnected
    private var _connectedDevice: ErgDevice?
    private var _sampleContinuation: AsyncStream<ErgTelemetrySample>.Continuation?
    private var _tick: Int = 0
    private var _elapsed: TimeInterval = 0
    private var _distance: Double = 0
    private var _rng: SeededGenerator
    private let _seed: UInt64
    private var _connectionAttemptID: UInt64 = 0
    private var _streamGeneration: UInt64 = 0

    public let basePace: TimeInterval
    public let baseCadence: Double
    public let baseWatts: Int
    public let baseHeartRate: Int?

    public init(
        basePace: TimeInterval = 125,
        baseCadence: Double = 26,
        baseWatts: Int = 200,
        baseHeartRate: Int? = 155,
        seed: UInt64 = 42
    ) {
        self.basePace = basePace
        self.baseCadence = baseCadence
        self.baseWatts = baseWatts
        self.baseHeartRate = baseHeartRate
        self._seed = seed
        self._rng = SeededGenerator(seed: seed)
    }

    public var currentState: ErgConnectionState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    public var connectedDevice: ErgDevice? {
        lock.lock()
        defer { lock.unlock() }
        return _connectedDevice
    }

    /// Simulate connecting to a device. Transitions through connecting → connected.
    public func connect(to device: ErgDevice) async throws {
        let attemptID = beginConnectionAttempt(to: device)

        do {
            try await Task.sleep(for: .milliseconds(10))
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
        let continuationToFinish: AsyncStream<ErgTelemetrySample>.Continuation?

        lock.lock()
        _connectionAttemptID += 1
        _state = .failed(reason: reason)
        _connectedDevice = nil
        continuationToFinish = _sampleContinuation
        _sampleContinuation = nil
        lock.unlock()

        continuationToFinish?.finish()
    }

    /// Emit a deterministic telemetry sample to the stream.
    ///
    /// Returns the emitted sample for assertion convenience.
    @discardableResult
    public func emitSample() -> ErgTelemetrySample {
        let sample: ErgTelemetrySample
        let continuation: AsyncStream<ErgTelemetrySample>.Continuation?

        lock.lock()

        _tick += 1
        let segmentDuration: TimeInterval = 1 // 1 second per tick
        _elapsed += segmentDuration

        // Pace varies ±3 sec/500m
        let paceVariation = Double(Int.random(in: -3 ... 3, using: &_rng))
        let currentPace = max(1.0, basePace + paceVariation)

        // Distance from pace: d = (segmentDuration / pace) * 500
        let segmentDistance = (segmentDuration / currentPace) * 500
        _distance += segmentDistance

        // Watts varies ±10
        let wattsVariation = Int.random(in: -10 ... 10, using: &_rng)
        let currentWatts = max(0, baseWatts + wattsVariation)

        // HR varies ±2 bpm
        let hrVariation = Int.random(in: -2 ... 2, using: &_rng)
        let currentHR = baseHeartRate.map { max(0, $0 + hrVariation) }
        let currentCadence = max(0, baseCadence + Double(Int.random(in: -1 ... 1, using: &_rng)))

        sample = ErgTelemetrySample(
            elapsed: _elapsed,
            distance: _distance,
            pace: currentPace,
            cadence: currentCadence,
            watts: currentWatts,
            heartRate: currentHR,
            timestamp: Date(timeIntervalSince1970: _elapsed)
        )
        continuation = _sampleContinuation
        lock.unlock()

        continuation?.yield(sample)
        return sample
    }

    /// Returns an async stream of telemetry samples.
    ///
    /// Samples are emitted when `emitSample()` is called, not on a timer.
    /// The stream finishes when `disconnect()` is called.
    public func telemetryStream() -> AsyncStream<ErgTelemetrySample> {
        let (stream, continuation) = AsyncStream<ErgTelemetrySample>.makeStream()
        let previousContinuation: AsyncStream<ErgTelemetrySample>.Continuation?
        let generation: UInt64

        lock.lock()
        previousContinuation = _sampleContinuation
        _streamGeneration += 1
        generation = _streamGeneration
        _sampleContinuation = continuation
        lock.unlock()

        continuation.onTermination = { [weak self] _ in
            self?.clearContinuation(generation: generation)
        }

        previousContinuation?.finish()
        return stream
    }

    /// Reset the mock to its initial state.
    public func reset() {
        let continuationToFinish: AsyncStream<ErgTelemetrySample>.Continuation?

        lock.lock()
        _connectionAttemptID += 1
        _state = .disconnected
        _connectedDevice = nil
        continuationToFinish = _sampleContinuation
        _sampleContinuation = nil
        _tick = 0
        _elapsed = 0
        _distance = 0
        _rng = SeededGenerator(seed: _seed)
        lock.unlock()

        continuationToFinish?.finish()
    }

    private func clearContinuation(generation: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if _streamGeneration == generation {
            _sampleContinuation = nil
        }
    }

    private func beginConnectionAttempt(to device: ErgDevice) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        _connectionAttemptID += 1
        _state = .connecting
        _connectedDevice = device
        return _connectionAttemptID
    }

    private func completeConnectionAttempt(_ attemptID: UInt64, device: ErgDevice) {
        lock.lock()
        defer { lock.unlock() }
        if _connectionAttemptID == attemptID, _state == .connecting, _connectedDevice == device {
            _state = .connected
        }
    }

    private func cancelConnectionAttempt(_ attemptID: UInt64) {
        lock.lock()
        defer { lock.unlock() }
        if _connectionAttemptID == attemptID, _state == .connecting {
            _state = .disconnected
            _connectedDevice = nil
        }
    }

    private func markDisconnectedAndTakeContinuation() -> AsyncStream<ErgTelemetrySample>.Continuation? {
        lock.lock()
        defer { lock.unlock() }
        _connectionAttemptID += 1
        _state = .disconnected
        _connectedDevice = nil
        let continuationToFinish = _sampleContinuation
        _sampleContinuation = nil
        return continuationToFinish
    }
}

// MARK: - ErgConnection Conformance

extension MockErgConnection: ErgConnection {}
