import Foundation

/// Live-mode status, mirroring the web's LiveModeStatus.
public enum LiveModeStatus: String, Sendable {
    case idle
    case polling
    case error
    case stopped
}

/// Pure value-type state machine for live-mode polling lifecycle.
///
/// The app layer owns a published instance and drives transitions from its
/// timer/callback layer. All transitions are explicit events so the state
/// machine is fully testable without Combine or timers.
public struct LiveModeState: Equatable, Sendable {
    public private(set) var enabled: Bool
    public private(set) var status: LiveModeStatus
    public private(set) var intervalSec: Int
    public private(set) var consecutiveFailures: Int
    public private(set) var lastPollAt: Date?
    public private(set) var nextPollAt: Date?

    public init(
        enabled: Bool = false,
        status: LiveModeStatus = .stopped,
        intervalSec: Int = 60,
        consecutiveFailures: Int = 0,
        lastPollAt: Date? = nil,
        nextPollAt: Date? = nil
    ) {
        self.enabled = enabled
        self.status = status
        self.intervalSec = liveIntervals.contains(intervalSec) ? intervalSec : 60
        self.consecutiveFailures = consecutiveFailures
        self.lastPollAt = lastPollAt
        self.nextPollAt = nextPollAt
    }

    /// Whether the agent has accumulated 3+ consecutive failures.
    public var hasWarning: Bool {
        consecutiveFailures >= 3
    }

    /// Whether the most recent sample exceeds the staleness threshold.
    public func isStale(lastSampleAge: TimeInterval) -> Bool {
        let threshold = LivePollingCadence.stalenessThreshold(intervalSec: intervalSec)
        return lastSampleAge > threshold
    }

    // MARK: - State Transitions

    /// Enable live mode and transition to idle.
    public mutating func start() {
        enabled = true
        status = .idle
        consecutiveFailures = 0
    }

    /// Disable live mode and transition to stopped.
    public mutating func stop() {
        enabled = false
        status = .stopped
        nextPollAt = nil
    }

    /// Mark a poll as in-progress. Valid when idle or in error state (retry).
    public mutating func pollStarted() {
        guard enabled, status == .idle || status == .error else { return }
        status = .polling
    }

    /// Mark a poll as succeeded, resetting backoff.
    public mutating func pollSucceeded(at date: Date = Date()) {
        guard enabled, status == .polling else { return }
        status = .idle
        consecutiveFailures = 0
        lastPollAt = date
    }

    /// Mark a poll as failed, incrementing the failure count.
    public mutating func pollFailed(at date: Date = Date()) {
        guard enabled, status == .polling else { return }
        status = .error
        consecutiveFailures += 1
        lastPollAt = date
    }

    /// Schedule the next poll at the given date.
    public mutating func tickScheduled(at date: Date) {
        guard enabled else { return }
        nextPollAt = date
    }

    /// Change the polling interval.
    public mutating func intervalChanged(_ newInterval: Int) {
        guard liveIntervals.contains(newInterval) else { return }
        intervalSec = newInterval
    }
}
