import Foundation

// MARK: - Response Envelopes

/// Top-level response from the workout summaries endpoint.
///
/// Matches: `GET /api/users/me/results`
/// Shape: `{ data: RawResult[], meta?: { pagination?: { total_pages?: number } } }`
struct Concept2WorkoutSummaryResponse: Decodable {
    let data: [Concept2RawResult]
    let meta: Concept2Meta?
}

/// Top-level response from the workout detail endpoint.
///
/// Matches: `GET /api/users/me/results/{id}?include=metadata`
/// Shape: `{ data: RawResult, metadata?: RawMetadata }`
struct Concept2WorkoutDetailResponse: Decodable {
    let data: Concept2RawResult
    let metadata: Concept2RawMetadata?
}

// MARK: - Pagination

struct Concept2Meta: Decodable {
    let pagination: Concept2Pagination?
}

struct Concept2Pagination: Decodable {
    let totalPages: Int?

    enum CodingKeys: String, CodingKey {
        case totalPages = "total_pages"
    }
}

// MARK: - Workout Result

/// A single workout result from the Concept2 logbook API.
///
/// Field names use snake_case matching the API JSON. Computed properties
/// provide the domain-mapped values.
struct Concept2RawResult: Decodable {
    let id: Int
    let date: String
    let type: String?
    let distance: Double
    let time: Double // tenths of a second
    let strokeRate: Double?
    let strokeCount: Int?
    let dragFactor: Int?
    let caloriesTotal: Int?
    let wattMinutes: Double?
    let workoutType: String?
    let comments: String?
    let strokeData: Bool?
    let source: String?
    let verified: Bool?
    let restTime: Double?
    let restDistance: Double?
    let heartRate: Concept2RawHeartRateValue?
    let workout: Concept2RawWorkout?
    let metadata: Concept2RawMetadata?

    enum CodingKeys: String, CodingKey {
        case id, date, type, distance, time
        case strokeRate = "stroke_rate"
        case strokeCount = "stroke_count"
        case dragFactor = "drag_factor"
        case caloriesTotal = "calories_total"
        case wattMinutes = "wattminutes_total"
        case workoutType = "workout_type"
        case comments
        case strokeData = "stroke_data"
        case source, verified
        case restTime = "rest_time"
        case restDistance = "rest_distance"
        case heartRate = "heart_rate"
        case workout, metadata
    }
}

// MARK: - Heart Rate

/// Heart rate data from the API. May be a simple number or a structured object.
///
/// Matches: `heart_rate?: number | { average?, min?, max? }`
enum Concept2RawHeartRateValue: Decodable {
    case number(Int)
    case object(Concept2RawHeartRate)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let num = try? container.decode(Int.self) {
            self = .number(num)
        } else {
            self = .object(try container.decode(Concept2RawHeartRate.self))
        }
    }
}

struct Concept2RawHeartRate: Decodable {
    let average: Int?
    let min: Int?
    let max: Int?
}

// MARK: - Workout Metadata

struct Concept2RawMetadata: Decodable {
    let pmVersion: Int?
    let firmwareVersion: String?
    let serialNumber: String?
    let device: String?

    enum CodingKeys: String, CodingKey {
        case pmVersion = "pm_version"
        case firmwareVersion = "firmware_version"
        case serialNumber = "serial_number"
        case device
    }
}

// MARK: - Workout Sub-Models

struct Concept2RawWorkout: Decodable {
    let splits: [Concept2RawSplit]?
    let intervals: [Concept2RawSplit]?
}

// MARK: - Splits

struct Concept2RawSplit: Decodable {
    let distance: Double?
    let time: Double? // tenths of a second
    let strokeRate: Int?
    let heartRate: Concept2RawHeartRateValue?
    let type: String?
    let restTime: Double?
    let restDistance: Double?
    let machine: String?

    enum CodingKeys: String, CodingKey {
        case distance, time
        case strokeRate = "stroke_rate"
        case heartRate = "heart_rate"
        case type
        case restTime = "rest_time"
        case restDistance = "rest_distance"
        case machine
    }
}

// MARK: - Strokes

struct Concept2RawStroke: Decodable {
    /// Time in tenths of a second.
    let t: Double
    /// Distance in decimetres.
    let d: Double
    /// Pace: per 500m for rower/skierg, per 1000m for bike. In tenths of a second.
    let p: Double
    /// Strokes per minute.
    let spm: Double
    /// Heart rate (optional).
    let hr: Int?
}
