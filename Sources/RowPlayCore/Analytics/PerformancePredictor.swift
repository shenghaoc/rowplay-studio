import Foundation

/// Paul's Law distance prediction engine.
///
/// Ports `src/lib/performancePredictor.ts` from the web app. Paul's Law is the
/// Concept2 community standard for estimating race times across distances:
/// `time₂ = time₁ × (distance₂ / distance₁)^1.06`.
public enum PerformancePredictor {
    /// Paul's Law exponent (Concept2 community standard).
    public static let paulExponent = 1.06

    /// Standard Concept2 race distances in metres.
    public static let predictorDistances: [Int] = [500, 1_000, 2_000, 5_000, 6_000, 10_000, 21_097]

    public enum PredictionStatus: String, Codable, Equatable, Sendable {
        case beaten
        case behind
        case untried
    }

    public struct PredictionRow: Equatable, Sendable {
        public let distance: Int
        public let predictedSeconds: Double
        public let actualBestSeconds: Double?
        public let status: PredictionStatus

        public init(
            distance: Int,
            predictedSeconds: Double,
            actualBestSeconds: Double?,
            status: PredictionStatus
        ) {
            self.distance = distance
            self.predictedSeconds = predictedSeconds
            self.actualBestSeconds = actualBestSeconds
            self.status = status
        }
    }

    // MARK: - Predictions

    /// Apply Paul's Law from one known (distance, time) pair.
    /// Returns predicted seconds for each standard distance; the source distance
    /// maps to `knownSeconds` exactly.
    public static func predictTimes(
        knownDistance: Int,
        knownSeconds: Double
    ) -> [Int: Double] {
        guard knownDistance > 0, knownSeconds > 0 else {
            return [:]
        }
        var out: [Int: Double] = [:]
        for d in predictorDistances {
            if d == knownDistance {
                out[d] = knownSeconds
            } else {
                out[d] = knownSeconds * pow(Double(d) / Double(knownDistance), paulExponent)
            }
        }
        return out
    }

    // MARK: - Prediction Table

    /// Build the full prediction table with status by comparing predictions
    /// against the athlete's personal bests (fastest time per distance wins).
    public static func buildPredictionTable(
        knownDistance: Int,
        knownSeconds: Double,
        personalBests: [(distance: Int, time: Double)]
    ) -> [PredictionRow] {
        guard knownDistance > 0, knownSeconds > 0 else {
            return []
        }

        var pbByDist: [Int: Double] = [:]
        for pb in personalBests {
            let current = pbByDist[pb.distance]
            if current == nil || pb.time < current! {
                pbByDist[pb.distance] = pb.time
            }
        }

        let predicted = predictTimes(knownDistance: knownDistance, knownSeconds: knownSeconds)

        return predictorDistances.map { distance in
            let predictedSeconds = predicted[distance] ?? 0
            let actualBestSeconds = pbByDist[distance]
            return PredictionRow(
                distance: distance,
                predictedSeconds: predictedSeconds,
                actualBestSeconds: actualBestSeconds,
                status: classifyStatus(predicted: predictedSeconds, actual: actualBestSeconds)
            )
        }
    }

    // MARK: - Private

    private static func classifyStatus(
        predicted: Double,
        actual: Double?
    ) -> PredictionStatus {
        guard let actual else {
            return .untried
        }
        return actual < predicted ? .beaten : .behind
    }
}
