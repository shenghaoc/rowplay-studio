import Foundation

/// Polling interval presets in seconds. Minimum 30 per Concept2 rate guidance.
public let liveIntervals: [Int] = [30, 60, 120, 300]

/// Minimum interval when the app is not frontmost, matching the web's HIDDEN_MIN_INTERVAL_SEC.
private let hiddenMinIntervalSec = 300

/// Stateless namespace for live-mode interval and backoff computation.
public enum LivePollingCadence {
    /// Active tab uses the configured interval; hidden tab slows to at least 5 minutes.
    public static func effectiveInterval(baseInterval: Int, isVisible: Bool) -> Int {
        if isVisible { return baseInterval }
        return max(baseInterval, hiddenMinIntervalSec)
    }

    /// Exponential backoff after failures: 30s → 60s → 120s → 300s cap.
    public static func nextBackoffMs(consecutiveFailures: Int) -> Int {
        if consecutiveFailures <= 0 { return 0 }
        let steps = [30_000, 60_000, 120_000, 300_000]
        return steps[min(consecutiveFailures - 1, steps.count - 1)]
    }

    /// Staleness threshold: 2× the configured interval in seconds.
    public static func stalenessThreshold(intervalSec: Int) -> TimeInterval {
        TimeInterval(intervalSec * 2)
    }

    /// Random delay for demo mock polls: 30s–3min, matching the web's randomMockDelayMs.
    public static func randomMockDelayMs() -> Int {
        30_000 + Int.random(in: 0 ..< 150_000)
    }
}
