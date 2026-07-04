import Foundation

public struct HeartRateDetail: Codable, Equatable, Sendable {
    public var average: Int?
    public var min: Int?
    public var max: Int?

    public init(average: Int? = nil, min: Int? = nil, max: Int? = nil) {
        self.average = average
        self.min = min
        self.max = max
    }
}

public struct Stroke: Codable, Equatable, Identifiable, Sendable {
    public var t: TimeInterval
    public var d: Double
    public var pace: TimeInterval
    public var cadence: Double
    public var heartRate: Int?
    public var watts: Int

    public var id: TimeInterval { t }

    public init(
        t: TimeInterval,
        d: Double,
        pace: TimeInterval,
        cadence: Double,
        heartRate: Int? = nil,
        watts: Int
    ) {
        self.t = t
        self.d = d
        self.pace = pace
        self.cadence = cadence
        self.heartRate = heartRate
        self.watts = watts
    }
}

public struct Split: Codable, Equatable, Identifiable, Sendable {
    public var index: Int
    public var distance: Double
    public var time: TimeInterval
    public var pace: TimeInterval
    public var cadence: Double?
    public var heartRate: HeartRateDetail?
    public var isRest: Bool?

    public var id: Int { index }

    public init(
        index: Int,
        distance: Double,
        time: TimeInterval,
        pace: TimeInterval,
        cadence: Double? = nil,
        heartRate: HeartRateDetail? = nil,
        isRest: Bool? = nil
    ) {
        self.index = index
        self.distance = distance
        self.time = time
        self.pace = pace
        self.cadence = cadence
        self.heartRate = heartRate
        self.isRest = isRest
    }
}

public struct Workout: Codable, Equatable, Identifiable, Sendable {
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
    public var source: String?
    public var verified: Bool
    public var hasStrokeData: Bool
    public var isInterval: Bool

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
        source: String? = nil,
        verified: Bool = true,
        hasStrokeData: Bool,
        isInterval: Bool = false
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
        self.source = source
        self.verified = verified
        self.hasStrokeData = hasStrokeData
        self.isInterval = isInterval
    }
}

public struct WorkoutDetail: Codable, Equatable, Identifiable, Sendable {
    public var workout: Workout
    public var strokes: [Stroke]
    public var splits: [Split]

    public var id: Int { workout.id }

    public init(workout: Workout, strokes: [Stroke], splits: [Split]) {
        self.workout = workout
        self.strokes = strokes
        self.splits = splits
    }
}
