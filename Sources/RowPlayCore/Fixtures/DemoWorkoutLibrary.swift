import Foundation

public enum DemoWorkoutLibrary {
    public static let defaultWorkoutID = 1001

    public static var details: [WorkoutDetail] {
        specs
            .map(buildDetail)
            .sorted { $0.workout.date > $1.workout.date }
    }

    private struct Spec {
        var id: Int
        var year: Int
        var month: Int
        var day: Int
        var hour: Int
        var minute: Int
        var sport: Sport
        var distance: Double
        var basePace: TimeInterval
        var baseCadence: Double
        var baseHeartRate: Int
        var workoutType: String
        var comments: String?
        var isInterval: Bool
        var source: String?
        var omitHeartRate: Bool
        var noStrokes: Bool
    }

    private static let specs: [Spec] = [
        Spec(
            id: 1001,
            year: 2026,
            month: 5,
            day: 27,
            hour: 6,
            minute: 12,
            sport: .rower,
            distance: 2_000,
            basePace: 108,
            baseCadence: 30,
            baseHeartRate: 168,
            workoutType: "2000m test",
            comments: "PB attempt - held on for the sprint.",
            isInterval: false,
            source: nil,
            omitHeartRate: false,
            noStrokes: false
        ),
        Spec(id: 1002, year: 2026, month: 5, day: 24, hour: 7, minute: 5, sport: .rower, distance: 5_000, basePace: 118, baseCadence: 26, baseHeartRate: 158, workoutType: "5000m steady", comments: nil, isInterval: false, source: nil, omitHeartRate: true, noStrokes: false),
        Spec(id: 1003, year: 2026, month: 5, day: 21, hour: 18, minute: 40, sport: .skierg, distance: 1_000, basePace: 122, baseCadence: 42, baseHeartRate: 165, workoutType: "1000m SkiErg", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1004, year: 2026, month: 5, day: 19, hour: 6, minute: 30, sport: .bike, distance: 8_000, basePace: 95, baseCadence: 85, baseHeartRate: 150, workoutType: "8000m BikeErg", comments: nil, isInterval: false, source: "EXR", omitHeartRate: false, noStrokes: false),
        Spec(id: 1005, year: 2026, month: 5, day: 16, hour: 6, minute: 20, sport: .rower, distance: 6_000, basePace: 116, baseCadence: 28, baseHeartRate: 160, workoutType: "4x1500m intervals", comments: nil, isInterval: true, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1006, year: 2026, month: 5, day: 13, hour: 18, minute: 15, sport: .rower, distance: 500, basePace: 96, baseCadence: 36, baseHeartRate: 172, workoutType: "500m sprint", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1007, year: 2026, month: 5, day: 10, hour: 6, minute: 18, sport: .rower, distance: 2_000, basePace: 112, baseCadence: 29, baseHeartRate: 166, workoutType: "2000m steady", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1008, year: 2026, month: 5, day: 6, hour: 7, minute: 0, sport: .skierg, distance: 1_000, basePace: 126, baseCadence: 40, baseHeartRate: 162, workoutType: "1000m SkiErg", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1009, year: 2026, month: 4, day: 29, hour: 6, minute: 25, sport: .rower, distance: 2_000, basePace: 113, baseCadence: 28, baseHeartRate: 167, workoutType: "2000m test", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1010, year: 2026, month: 4, day: 22, hour: 6, minute: 30, sport: .rower, distance: 2_000, basePace: 115, baseCadence: 28, baseHeartRate: 168, workoutType: "2000m test", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1011, year: 2026, month: 4, day: 15, hour: 6, minute: 28, sport: .rower, distance: 2_000, basePace: 117, baseCadence: 27, baseHeartRate: 169, workoutType: "2000m test", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 9001, year: 2024, month: 1, day: 15, hour: 4, minute: 30, sport: .rower, distance: 5_000, basePace: 126, baseCadence: 28, baseHeartRate: 160, workoutType: "5000m steady", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: true),
        Spec(id: 1012, year: 2026, month: 4, day: 8, hour: 6, minute: 0, sport: .rower, distance: 7_500, basePace: 120, baseCadence: 26, baseHeartRate: 160, workoutType: "JustRow", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1013, year: 2026, month: 4, day: 5, hour: 6, minute: 0, sport: .rower, distance: 1_000, basePace: 170, baseCadence: 18, baseHeartRate: 118, workoutType: "Warm-up", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1014, year: 2026, month: 4, day: 3, hour: 6, minute: 0, sport: .rower, distance: 3_500, basePace: 132, baseCadence: 24, baseHeartRate: 145, workoutType: "Technique drills", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1015, year: 2026, month: 3, day: 28, hour: 7, minute: 10, sport: .skierg, distance: 5_000, basePace: 132, baseCadence: 38, baseHeartRate: 155, workoutType: "5000m SkiErg steady", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false),
        Spec(id: 1016, year: 2026, month: 3, day: 22, hour: 7, minute: 10, sport: .bike, distance: 2_000, basePace: 88, baseCadence: 92, baseHeartRate: 165, workoutType: "2000m BikeErg time trial", comments: nil, isInterval: false, source: nil, omitHeartRate: false, noStrokes: false)
    ]

    private static func buildDetail(from spec: Spec) -> WorkoutDetail {
        let strokes = spec.noStrokes ? [] : buildStrokes(from: spec)
        let time = strokes.last?.t ?? spec.distance * spec.basePace / 500
        let pace = time / (spec.distance / 500)
        let averageWatts = RowPlayFormatting.paceToWatts(for: spec.sport, pacePer500m: pace)
        let heartRateAverage = spec.omitHeartRate ? nil : Int((Double(spec.baseHeartRate) * 0.91).rounded())
        let workout = Workout(
            id: spec.id,
            date: makeDate(year: spec.year, month: spec.month, day: spec.day, hour: spec.hour, minute: spec.minute),
            sport: spec.sport,
            distance: spec.distance,
            time: time,
            pace: pace,
            strokeRate: spec.baseCadence,
            strokeCount: Int((time / 60 * spec.baseCadence).rounded()),
            heartRateAvg: heartRateAverage,
            caloriesTotal: Int((averageWatts * time / 1_000).rounded()),
            wattMinutes: averageWatts * time / 60,
            dragFactor: spec.sport == .bike ? nil : 124,
            workoutType: spec.workoutType,
            comments: spec.comments,
            source: spec.source,
            verified: true,
            hasStrokeData: !strokes.isEmpty,
            isInterval: spec.isInterval
        )

        return WorkoutDetail(
            workout: workout,
            strokes: strokes,
            splits: buildSplits(for: spec, strokes: strokes, workoutTime: time)
        )
    }

    private static func buildStrokes(from spec: Spec) -> [Stroke] {
        var random = SeededRandom(seed: UInt32(spec.id))
        var strokes: [Stroke] = []
        var distance = 0.0
        var time = 0.0
        let distanceStep = spec.distance / 220

        while distance < spec.distance {
            let fraction = distance / spec.distance
            let noise = (random.next() - 0.5) * 4
            let pace = max(70, spec.basePace * paceProfile(fraction) + noise)
            let speed = 500 / pace
            let deltaTime = distanceStep / speed
            time += deltaTime
            distance += distanceStep

            let lateSurge = fraction > 0.9 ? 4.0 : 0
            let cadence = spec.baseCadence + lateSurge + (random.next() - 0.5) * 2
            var heartRate: Int?
            if !spec.omitHeartRate {
                let baseHeartRate = Double(spec.baseHeartRate)
                let progression = baseHeartRate * (0.8 + fraction * 0.22)
                let jitter = (random.next() - 0.5) * 3
                heartRate = Int(min(192, progression + jitter).rounded())
            }

            strokes.append(
                Stroke(
                    t: roundToTenth(time),
                    d: roundToTenth(min(distance, spec.distance)),
                    pace: roundToTenth(pace),
                    cadence: cadence.rounded(),
                    heartRate: heartRate,
                    watts: Int(RowPlayFormatting.paceToWatts(for: spec.sport, pacePer500m: pace).rounded())
                )
            )
        }

        return strokes
    }

    private static func buildSplits(for spec: Spec, strokes: [Stroke], workoutTime: TimeInterval) -> [Split] {
        let splitCount = spec.isInterval ? 4 : min(5, max(1, Int((spec.distance / 1_000).rounded(.up))))
        let splitDistance = spec.distance / Double(splitCount)

        return (0..<splitCount).map { index in
            let startDistance = Double(index) * splitDistance
            let endDistance = Double(index + 1) * splitDistance
            let startTime = time(atDistance: startDistance, in: strokes, fallbackTotalDistance: spec.distance, fallbackTotalTime: workoutTime)
            let endTime = time(atDistance: endDistance, in: strokes, fallbackTotalDistance: spec.distance, fallbackTotalTime: workoutTime)
            let duration = max(0, endTime - startTime)
            let splitPace = duration > 0 ? duration / (splitDistance / 500) : spec.basePace
            let heartRate = spec.omitHeartRate ? nil : HeartRateDetail(average: spec.baseHeartRate, min: spec.baseHeartRate - 12, max: spec.baseHeartRate + 10)

            return Split(
                index: index + 1,
                distance: splitDistance,
                time: duration,
                pace: splitPace,
                cadence: spec.baseCadence,
                heartRate: heartRate
            )
        }
    }

    private static func time(atDistance distance: Double, in strokes: [Stroke], fallbackTotalDistance: Double, fallbackTotalTime: TimeInterval) -> TimeInterval {
        guard !strokes.isEmpty else {
            return fallbackTotalDistance > 0 ? fallbackTotalTime * (distance / fallbackTotalDistance) : 0
        }
        if distance <= 0 {
            return 0
        }
        return strokes.first { $0.d >= distance }?.t ?? strokes.last?.t ?? 0
    }

    private static func paceProfile(_ fraction: Double) -> Double {
        if fraction < 0.08 {
            return 1.06 - fraction
        }
        if fraction > 0.9 {
            return 0.9 - (fraction - 0.9) * 0.6
        }
        return 1.0 - fraction * 0.06
    }

    private static func roundToTenth(_ value: Double) -> Double {
        (value * 10).rounded() / 10
    }

    private static func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return components.date ?? Date(timeIntervalSince1970: 0)
    }
}

private struct SeededRandom {
    private var state: UInt32

    init(seed: UInt32) {
        state = seed
    }

    mutating func next() -> Double {
        state = state &* 1_664_525 &+ 1_013_904_223
        return Double(state) / Double(UInt32.max)
    }
}
