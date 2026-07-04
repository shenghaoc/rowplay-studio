import Foundation

/// One point-in-time hardware telemetry reading from an ergometer.
///
/// Field names and units align with existing `Stroke` and `LiveWorkoutSample`
/// models where applicable:
/// - `elapsed` matches `Stroke.t` / `LiveWorkoutSample.time`
/// - `distance` matches `Stroke.d` / `LiveWorkoutSample.distance`
/// - `pace` matches `Stroke.pace` / `LiveWorkoutSample.pace` (seconds per 500m)
/// - `cadence` matches `Stroke.cadence` (strokes/min or rpm)
/// - `watts` matches `Stroke.watts`
/// - `heartRate` matches `Stroke.heartRate`
public struct ErgTelemetrySample: Equatable, Codable, Sendable {
    public let elapsed: TimeInterval
    public let distance: Double
    public let pace: TimeInterval
    public let cadence: Double
    public let watts: Int
    public let heartRate: Int?
    public let timestamp: Date

    public init(
        elapsed: TimeInterval,
        distance: Double,
        pace: TimeInterval,
        cadence: Double,
        watts: Int,
        heartRate: Int? = nil,
        timestamp: Date = Date()
    ) {
        self.elapsed = elapsed
        self.distance = distance
        self.pace = pace
        self.cadence = cadence
        self.watts = watts
        self.heartRate = heartRate
        self.timestamp = timestamp
    }
}
