import Foundation

/// A local replay package for offline sharing without a companion web service.
///
/// Captures a workout detail plus metadata, with hardware-identifying fields redacted.
public struct SharePackage: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var schema: String
    public var version: Int
    public var exportedAt: Date
    public var workout: WorkoutSummary
    public var strokes: [Stroke]
    public var splits: [Split]

    public init(
        schema: String = "rowplay-share-package",
        version: Int = SharePackage.currentVersion,
        exportedAt: Date = Date(),
        workout: WorkoutSummary,
        strokes: [Stroke],
        splits: [Split]
    ) {
        self.schema = schema
        self.version = version
        self.exportedAt = exportedAt
        self.workout = workout
        self.strokes = strokes
        self.splits = splits
    }

    /// Workout summary with privacy-safe fields only.
    public struct WorkoutSummary: Codable, Equatable, Sendable {
        public var id: Int
        public var date: Date
        public var sport: Sport
        public var distance: Double
        public var time: TimeInterval
        public var pace: TimeInterval
        public var strokeRate: Double?
        public var strokeCount: Int?
        public var heartRateAvg: Int?
        public var caloriesTotal: Int?
        public var wattMinutes: Double?
        public var dragFactor: Int?
        public var workoutType: String
        public var comments: String?
        public var hasStrokeData: Bool
        public var isInterval: Bool

        /// Non-sensitive metadata only (no serialNumber, device, deviceOs, deviceOsVersion).
        public var pmVersion: Int?
        public var firmwareVersion: String?
        public var ergModelType: Int?
        public var hrType: String?

        public init(
            id: Int,
            date: Date,
            sport: Sport,
            distance: Double,
            time: TimeInterval,
            pace: TimeInterval,
            strokeRate: Double? = nil,
            strokeCount: Int? = nil,
            heartRateAvg: Int? = nil,
            caloriesTotal: Int? = nil,
            wattMinutes: Double? = nil,
            dragFactor: Int? = nil,
            workoutType: String,
            comments: String? = nil,
            hasStrokeData: Bool,
            isInterval: Bool = false,
            pmVersion: Int? = nil,
            firmwareVersion: String? = nil,
            ergModelType: Int? = nil,
            hrType: String? = nil
        ) {
            self.id = id
            self.date = date
            self.sport = sport
            self.distance = distance
            self.time = time
            self.pace = pace
            self.strokeRate = strokeRate
            self.strokeCount = strokeCount
            self.heartRateAvg = heartRateAvg
            self.caloriesTotal = caloriesTotal
            self.wattMinutes = wattMinutes
            self.dragFactor = dragFactor
            self.workoutType = workoutType
            self.comments = comments
            self.hasStrokeData = hasStrokeData
            self.isInterval = isInterval
            self.pmVersion = pmVersion
            self.firmwareVersion = firmwareVersion
            self.ergModelType = ergModelType
            self.hrType = hrType
        }
    }
}

public enum SharePackageBuilder: Sendable {
    /// Build a SharePackage from a WorkoutDetail, stripping hardware-identifying metadata.
    public static func build(from detail: WorkoutDetail) -> SharePackage {
        let w = detail.workout
        let summary = SharePackage.WorkoutSummary(
            id: w.id,
            date: w.date,
            sport: w.sport,
            distance: w.distance,
            time: w.time,
            pace: w.pace,
            strokeRate: w.strokeRate,
            strokeCount: w.strokeCount,
            heartRateAvg: w.heartRateAvg,
            caloriesTotal: w.caloriesTotal,
            wattMinutes: w.wattMinutes,
            dragFactor: w.dragFactor,
            workoutType: w.workoutType,
            comments: w.comments,
            hasStrokeData: w.hasStrokeData,
            isInterval: w.isInterval
            // Non-sensitive metadata fields left nil for now since native Workout
            // doesn't carry them yet. When it does, populate pmVersion, firmwareVersion,
            // ergModelType, hrType here — but NEVER serialNumber, device, deviceOs, deviceOsVersion.
        )
        return SharePackage(
            workout: summary,
            strokes: detail.strokes,
            splits: detail.splits
        )
    }
}

public enum SharePackageCodec: Sendable {
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

    /// Encode a SharePackage to JSON data.
    public static func encode(_ package: SharePackage) throws -> Data {
        try encoder.encode(package)
    }

    /// Decode a SharePackage from JSON data.
    public static func decode(_ data: Data) throws -> SharePackage {
        try decoder.decode(SharePackage.self, from: data)
    }
}
