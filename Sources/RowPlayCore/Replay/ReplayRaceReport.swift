import Foundation

/// Versioned, privacy-safe local race report for offline export/share.
///
/// Excludes tokens, comments, full filesystem paths, imported filenames,
/// hardware identifiers, account identifiers, raw logs, and public URLs.
public struct ReplayRaceReport: Codable, Equatable, Sendable {
    public static let currentSchema = "rowplay-race-report"
    /// Rival performance metrics are additive optional fields in version 1.
    /// Keeping the version stable lets current decoders read older version-1
    /// reports that predate those fields, while older decoders can ignore them.
    public static let currentVersion = 1

    public var schema: String
    public var version: Int
    public var exportedAt: Date
    public var sport: Sport
    public var target: RaceTarget
    public var primary: ParticipantSummary
    public var rival: RivalSummary
    public var outcome: ReplayRaceOutcome
    public var timeMargin: TimeInterval?
    public var distanceMargin: Double?
    public var rivalDidNotFinish: Bool

    public init(
        schema: String = ReplayRaceReport.currentSchema,
        version: Int = ReplayRaceReport.currentVersion,
        exportedAt: Date = Date(),
        sport: Sport,
        target: RaceTarget,
        primary: ParticipantSummary,
        rival: RivalSummary,
        outcome: ReplayRaceOutcome,
        timeMargin: TimeInterval? = nil,
        distanceMargin: Double? = nil,
        rivalDidNotFinish: Bool = false
    ) {
        self.schema = schema
        self.version = version
        self.exportedAt = exportedAt
        self.sport = sport
        self.target = target
        self.primary = primary
        self.rival = rival
        self.outcome = outcome
        self.timeMargin = timeMargin
        self.distanceMargin = distanceMargin
        self.rivalDidNotFinish = rivalDidNotFinish
    }

    public struct RaceTarget: Codable, Equatable, Sendable {
        public var axis: String
        public var distance: Double?
        public var duration: TimeInterval?

        public init(axis: ComparabilityAxis, distance: Double? = nil, duration: TimeInterval? = nil) {
            self.axis = axis.rawValue
            self.distance = distance
            self.duration = duration
        }
    }

    public struct ParticipantSummary: Codable, Equatable, Sendable {
        public var date: Date
        public var distance: Double
        public var time: TimeInterval
        public var pace: TimeInterval

        public init(
            date: Date,
            distance: Double,
            time: TimeInterval,
            pace: TimeInterval
        ) {
            self.date = date
            self.distance = distance
            self.time = time
            self.pace = pace
        }
    }

    /// Sanitized rival kind and metrics only — never filenames or paths.
    public struct RivalSummary: Codable, Equatable, Sendable {
        public var kind: ReplayRivalKind
        public var sessionDate: Date?
        public var targetPace: TimeInterval?
        /// Rival distance represented by the completed result. For a
        /// distance-axis DNF this is the distance reached at the player's
        /// finish; otherwise it is the target/final distance.
        public var distance: Double?
        /// Rival elapsed time represented by the completed result. For a
        /// distance-axis DNF this is the observation time at player finish.
        public var time: TimeInterval?
        /// Privacy-safe average pace derived from `distance` and `time`, or
        /// the accepted pace-boat target when that is more precise.
        public var pace: TimeInterval?
        /// Generic label for reports ("Past session", "Pace boat", "Imported rival").
        public var label: String

        public init(
            kind: ReplayRivalKind,
            sessionDate: Date? = nil,
            targetPace: TimeInterval? = nil,
            distance: Double? = nil,
            time: TimeInterval? = nil,
            pace: TimeInterval? = nil,
            label: String
        ) {
            self.kind = kind
            self.sessionDate = sessionDate
            self.targetPace = Self.sanitizedPositive(targetPace)
            self.distance = Self.sanitizedNonNegative(distance)
            self.time = Self.sanitizedNonNegative(time)
            self.pace = Self.sanitizedPositive(pace)
            self.label = label
        }

        private static func sanitizedNonNegative(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value >= 0 else { return nil }
            return value
        }

        private static func sanitizedPositive(_ value: Double?) -> Double? {
            guard let value, value.isFinite, value > 0 else { return nil }
            return value
        }
    }
}

public enum ReplayRaceReportBuilder: Sendable {
    /// Build a privacy-safe race report from a completed result.
    public static func build(
        player: Workout,
        rival: ReplayRival,
        result: ReplayRaceResult,
        sessionDate: Date? = nil,
        exportedAt: Date = Date()
    ) -> ReplayRaceReport {
        let axis = result.axis
        let target: ReplayRaceReport.RaceTarget
        switch axis {
        case .distance:
            target = .init(axis: .distance, distance: player.distance, duration: nil)
        case .time:
            target = .init(axis: .time, distance: nil, duration: player.time)
        }

        let metrics = rivalMetrics(player: player, rival: rival, result: result)

        let rivalSummary: ReplayRaceReport.RivalSummary
        switch rival.kind {
        case .session:
            rivalSummary = .init(
                kind: .session,
                sessionDate: sessionDate,
                distance: metrics.distance,
                time: metrics.time,
                pace: metrics.pace,
                label: "Past session"
            )
        case .constantPace:
            rivalSummary = .init(
                kind: .constantPace,
                targetPace: rival.targetPace,
                distance: metrics.distance,
                time: metrics.time,
                pace: metrics.pace,
                label: "Pace boat"
            )
        case .importedFile:
            // Never include localFileName in the report.
            rivalSummary = .init(
                kind: .importedFile,
                distance: metrics.distance,
                time: metrics.time,
                pace: metrics.pace,
                label: "Imported rival"
            )
        }

        let primaryMetrics = primaryMetrics(player: player, result: result)

        return ReplayRaceReport(
            exportedAt: exportedAt,
            sport: player.sport,
            target: target,
            primary: .init(
                date: player.date,
                distance: primaryMetrics.distance,
                time: primaryMetrics.time,
                pace: primaryMetrics.pace
            ),
            rival: rivalSummary,
            outcome: result.outcome,
            timeMargin: result.timeMargin,
            distanceMargin: result.distanceMargin,
            rivalDidNotFinish: result.rivalDidNotFinish
        )
    }

    /// Build the primary participant's completed race summary. A distance race
    /// uses the target distance and the player's own crossing time; the
    /// decision-point distance stored for a rival win is reserved for the
    /// shortfall margin. A time race uses the distance sampled at the target
    /// duration.
    private static func primaryMetrics(
        player: Workout,
        result: ReplayRaceResult
    ) -> (distance: Double, time: TimeInterval, pace: TimeInterval) {
        let distance: Double
        switch result.axis {
        case .distance:
            distance = player.distance
        case .time:
            distance = result.playerDistance ?? player.distance
        }

        let time = result.playerFinishTime ?? player.time
        let derivedPace: TimeInterval? = {
            guard distance.isFinite, distance > 0, time.isFinite, time > 0 else { return nil }
            let value = time * 500.0 / distance
            return value.isFinite && value > 0 ? value : nil
        }()
        let pace = derivedPace ?? player.pace
        return (
            distance: distance.isFinite && distance >= 0 ? distance : player.distance,
            time: time.isFinite && time >= 0 ? time : player.time,
            pace: pace.isFinite && pace > 0 ? pace : player.pace
        )
    }

    private struct RivalMetrics {
        let distance: Double?
        let time: TimeInterval?
        let pace: TimeInterval?
    }

    /// Selects a coherent time/distance pair from the result. Completed
    /// distance rivals use their target finish; a DNF uses the player's finish
    /// as the observation point; time-axis races use the target duration.
    private static func rivalMetrics(
        player: Workout,
        rival: ReplayRival,
        result: ReplayRaceResult
    ) -> RivalMetrics {
        let distance: Double?
        let time: TimeInterval?

        switch result.axis {
        case .distance:
            if let rivalFinishTime = result.rivalFinishTime {
                distance = player.distance
                time = rivalFinishTime
            } else if result.rivalDidNotFinish {
                distance = result.rivalDistance
                time = result.playerFinishTime
            } else {
                distance = nil
                time = nil
            }
        case .time:
            distance = result.rivalDistance
            time = result.rivalFinishTime ?? result.playerFinishTime
        }

        let derivedPace: TimeInterval? = {
            guard let distance, distance.isFinite, distance > 0,
                  let time, time.isFinite, time > 0 else {
                return nil
            }
            let value = time * 500 / distance
            return value.isFinite && value > 0 ? value : nil
        }()
        let acceptedTargetPace = rival.targetPace.flatMap {
            $0.isFinite && $0 > 0 ? $0 : nil
        }

        return RivalMetrics(
            distance: distance,
            time: time,
            pace: acceptedTargetPace ?? derivedPace
        )
    }
}

public enum ReplayRaceReportCodec: Sendable {
    private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }

    private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func encode(_ report: ReplayRaceReport) throws -> Data {
        try makeEncoder().encode(report)
    }

    public static func decode(_ data: Data) throws -> ReplayRaceReport {
        try makeDecoder().decode(ReplayRaceReport.self, from: data)
    }
}
