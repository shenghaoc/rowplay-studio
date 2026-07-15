import Foundation

/// Versioned, privacy-safe local race report for offline export/share.
///
/// Excludes tokens, comments, full filesystem paths, imported filenames,
/// hardware identifiers, account identifiers, raw logs, and public URLs.
public struct ReplayRaceReport: Codable, Equatable, Sendable {
    public static let currentSchema = "rowplay-race-report"
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
        public var workoutID: Int
        public var date: Date
        public var distance: Double
        public var time: TimeInterval
        public var pace: TimeInterval

        public init(
            workoutID: Int,
            date: Date,
            distance: Double,
            time: TimeInterval,
            pace: TimeInterval
        ) {
            self.workoutID = workoutID
            self.date = date
            self.distance = distance
            self.time = time
            self.pace = pace
        }
    }

    /// Sanitized rival kind and metrics only — never filenames or paths.
    public struct RivalSummary: Codable, Equatable, Sendable {
        public var kind: ReplayRivalKind
        public var sessionWorkoutID: Int?
        public var sessionDate: Date?
        public var targetPace: TimeInterval?
        /// Generic label for reports ("Past session", "Pace boat", "Imported rival").
        public var label: String

        public init(
            kind: ReplayRivalKind,
            sessionWorkoutID: Int? = nil,
            sessionDate: Date? = nil,
            targetPace: TimeInterval? = nil,
            label: String
        ) {
            self.kind = kind
            self.sessionWorkoutID = sessionWorkoutID
            self.sessionDate = sessionDate
            self.targetPace = targetPace
            self.label = label
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

        let rivalSummary: ReplayRaceReport.RivalSummary
        switch rival.kind {
        case .session:
            rivalSummary = .init(
                kind: .session,
                sessionWorkoutID: rival.sessionWorkoutID,
                sessionDate: sessionDate,
                label: "Past session"
            )
        case .constantPace:
            rivalSummary = .init(
                kind: .constantPace,
                targetPace: rival.targetPace,
                label: "Pace boat"
            )
        case .importedFile:
            // Never include localFileName in the report.
            rivalSummary = .init(
                kind: .importedFile,
                label: "Imported rival"
            )
        }

        return ReplayRaceReport(
            exportedAt: exportedAt,
            sport: player.sport,
            target: target,
            primary: .init(
                workoutID: player.id,
                date: player.date,
                distance: player.distance,
                time: player.time,
                pace: player.pace
            ),
            rival: rivalSummary,
            outcome: result.outcome,
            timeMargin: result.timeMargin,
            distanceMargin: result.distanceMargin,
            rivalDidNotFinish: result.rivalDidNotFinish
        )
    }
}

public enum ReplayRaceReportCodec: Sendable {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    public static func encode(_ report: ReplayRaceReport) throws -> Data {
        try encoder.encode(report)
    }

    public static func decode(_ data: Data) throws -> ReplayRaceReport {
        try decoder.decode(ReplayRaceReport.self, from: data)
    }
}
