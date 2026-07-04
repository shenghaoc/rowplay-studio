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
        lock.lock()
        _state = .connecting
        _connectedDevice = device
        lock.unlock()

        // Simulate a brief connection delay
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms

        lock.lock()
        _state = .connected
        lock.unlock()
    }

    /// Disconnect from the current device.
    public func disconnect() async {
        lock.lock()
        _state = .disconnected
        _connectedDevice = nil
        _sampleContinuation?.finish()
        _sampleContinuation = nil
        lock.unlock()
    }

    /// Simulate a connection failure with a human-readable reason.
    public func simulateFailure(reason: String) {
        lock.lock()
        defer { lock.unlock() }
        _state = .failed(reason: reason)
    }

    /// Emit a deterministic telemetry sample to the stream.
    ///
    /// Returns the emitted sample for assertion convenience.
    @discardableResult
    public func emitSample() -> ErgTelemetrySample {
        lock.lock()
        defer { lock.unlock() }

        _tick += 1
        let segmentDuration: TimeInterval = 1 // 1 second per tick
        _elapsed += segmentDuration

        // Pace varies ±3 sec/500m
        let paceVariation = Double(Int.random(in: -3 ... 3, using: &_rng))
        let currentPace = basePace + paceVariation

        // Distance from pace: d = (segmentDuration / pace) * 500
        let segmentDistance = (segmentDuration / currentPace) * 500
        _distance += segmentDistance

        // Watts varies ±10
        let wattsVariation = Int.random(in: -10 ... 10, using: &_rng)
        let currentWatts = baseWatts + wattsVariation

        // HR varies ±2 bpm
        let hrVariation = Int.random(in: -2 ... 2, using: &_rng)
        let currentHR = baseHeartRate.map { $0 + hrVariation }

        let sample = ErgTelemetrySample(
            elapsed: _elapsed,
            distance: _distance,
            pace: currentPace,
            cadence: baseCadence + Double(Int.random(in: -1 ... 1, using: &_rng)),
            watts: currentWatts,
            heartRate: currentHR,
            timestamp: Date()
        )

        _sampleContinuation?.yield(sample)
        return sample
    }

    /// Returns an async stream of telemetry samples.
    ///
    /// Samples are emitted when `emitSample()` is called, not on a timer.
    /// The stream finishes when `disconnect()` is called.
    public func telemetryStream() -> AsyncStream<ErgTelemetrySample> {
        lock.lock()
        defer { lock.unlock() }

        let (stream, continuation) = AsyncStream<ErgTelemetrySample>.makeStream()
        _sampleContinuation = continuation
        return stream
    }

    /// Reset the mock to its initial state.
    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _state = .disconnected
        _connectedDevice = nil
        _sampleContinuation?.finish()
        _sampleContinuation = nil
        _tick = 0
        _elapsed = 0
        _distance = 0
        _rng = SeededGenerator(seed: 42)
    }
}

// MARK: - ErgConnection Conformance

extension MockErgConnection: ErgConnection {}
