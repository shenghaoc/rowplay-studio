import Foundation

/// Maps raw Concept2 API responses to RowPlayCore domain types.
///
/// Unit normalization (matching the web app's `concept2.ts`):
/// - API `time` is in tenths of a second → divide by 10 for seconds.
/// - API `stroke.t` is in tenths of a second → divide by 10 for seconds.
/// - API `stroke.d` is in decimetres → divide by 10 for metres.
/// - API `stroke.p` is pace in tenths of a second (per 500m for rower/skierg,
///   per 1000m for bike) → divide by 10, then by 2 for bike to normalise to
///   seconds per 500m.
enum Concept2Mapper {
    /// Date formatter for Concept2 API timestamps ("yyyy-MM-dd HH:mm:ss").
    static let apiDateFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd HH:mm:ss"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        return fmt
    }()

    // MARK: - Workout Summary

    /// Map a raw API result to a domain `Workout`.
    static func mapWorkout(_ raw: Concept2RawResult) -> Workout {
        let sport = Sport.fromConcept2Type(raw.type)
        let timeSeconds = raw.time / 10
        let distance = raw.distance
        let pace = distance > 0 ? timeSeconds / (distance / 500) : 0
        let heartRate = mapHeartRateValue(raw.heartRate)

        return Workout(
            id: raw.id,
            date: apiDateFormatter.date(from: raw.date) ?? Date(timeIntervalSince1970: 0),
            sport: sport,
            distance: distance,
            time: timeSeconds,
            pace: pace,
            strokeRate: raw.strokeRate,
            strokeCount: raw.strokeCount,
            heartRateAvg: heartRate?.average,
            caloriesTotal: raw.caloriesTotal,
            wattMinutes: raw.wattMinutes,
            dragFactor: raw.dragFactor,
            workoutType: raw.workoutType ?? "JustRow",
            comments: raw.comments,
            source: raw.source,
            verified: raw.verified ?? true,
            hasStrokeData: raw.strokeData ?? false,
            isInterval: raw.workout?.intervals?.isEmpty == false
        )
    }

    // MARK: - Heart Rate

    /// Map a raw heart rate value (number or object) to `HeartRateDetail`.
    static func mapHeartRate(_ raw: Concept2RawHeartRate?) -> HeartRateDetail? {
        guard let raw else { return nil }
        return HeartRateDetail(average: raw.average, min: raw.min, max: raw.max)
    }

    static func mapHeartRateValue(_ raw: Concept2RawHeartRateValue?) -> HeartRateDetail? {
        guard let raw else { return nil }
        switch raw {
        case let .number(n):
            return HeartRateDetail(average: n)
        case let .object(hr):
            return mapHeartRate(hr)
        }
    }

    // MARK: - Strokes

    /// Map raw strokes to domain `Stroke` values with unit normalization.
    ///
    /// Handles the bike pace divisor (per-1000m → per-500m) and interval
    /// time/distance offset accumulation (the API resets `t`/`d` each rep).
    static func mapStrokes(_ raw: [Concept2RawStroke], sport: Sport) -> [Stroke] {
        let paceDiv = sport == .bike ? 2.0 : 1.0
        var tOffset: Double = 0
        var dOffset: Double = 0
        var prevT: Double = 0
        var prevD: Double = 0

        return raw.map { s in
            let rawT = s.t / 10
            let rawD = s.d / 10
            if rawT < prevT { tOffset += prevT }
            if rawD < prevD { dOffset += prevD }
            prevT = rawT
            prevD = rawD

            let pace = s.p / 10 / paceDiv
            return Stroke(
                t: rawT + tOffset,
                d: rawD + dOffset,
                pace: pace,
                cadence: s.spm,
                heartRate: s.hr,
                watts: paceToWatts(sport: sport, pace: pace)
            )
        }
    }

    // MARK: - Splits

    /// Map raw splits to domain `Split` values.
    static func mapSplits(_ raw: Concept2RawResult) -> [Split] {
        let rawSplits = raw.workout?.splits ?? raw.workout?.intervals ?? []
        return rawSplits.enumerated().map { i, s in
            let time = (s.time ?? 0) / 10
            let distance = s.distance ?? 0
            let pace = distance > 0 ? time / (distance / 500) : 0
            let heartRate = mapHeartRateValue(s.heartRate)
            let isRest = distance == 0 && time > 0

            return Split(
                index: i,
                distance: distance,
                time: time,
                pace: pace,
                cadence: Double(s.strokeRate ?? 0),
                heartRate: heartRate,
                isRest: isRest
            )
        }
    }

    // MARK: - Watts Calculation

    /// Convert pace (seconds per 500m) to watts using the Concept2 formula.
    ///
    /// Matches `paceToWattsForSport` in the web app's `format.ts`.
    /// For bike: pace is seconds per 1000m. For rower/skierg: seconds per 500m.
    static func paceToWatts(sport: Sport, pace: Double) -> Int {
        guard pace > 0 else { return 0 }
        // Concept2 formula: watts = 2.80 / pace³ (pace in seconds per metre)
        let pacePerMetre: Double
        switch sport {
        case .bike:
            pacePerMetre = pace / 1000
        case .rower, .skierg:
            pacePerMetre = pace / 500
        }
        guard pacePerMetre > 0 else { return 0 }
        let watts = 2.80 / (pacePerMetre * pacePerMetre * pacePerMetre)
        guard watts.isFinite, watts <= Double(Int.max) else { return 0 }
        return Int(watts.rounded())
    }
}
