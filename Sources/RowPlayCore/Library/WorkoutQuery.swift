import Foundation

// MARK: - Sort

public enum WorkoutSortField: String, CaseIterable, Sendable {
    case date
    case distance
    case time
    case pace
    case power
}

public enum SortDir: String, Sendable {
    case asc
    case desc
}

// MARK: - Query

public struct WorkoutListQuery: Equatable, Sendable {
    public var sport: Sport?
    public var workoutType: String?
    public var dateFrom: String?
    public var dateTo: String?
    /// Nominal metres for a distance chip (500, 2000, …).
    public var distanceM: Double?
    public var hasStroke: Bool?
    /// Free-text match against comments/workoutType/sport.
    public var searchText: String?
    public var pbsOnly: Bool
    public var durationMin: TimeInterval?
    public var durationMax: TimeInterval?
    public var sort: WorkoutSortField
    public var dir: SortDir

    public init(
        sport: Sport? = nil,
        workoutType: String? = nil,
        dateFrom: String? = nil,
        dateTo: String? = nil,
        distanceM: Double? = nil,
        hasStroke: Bool? = nil,
        searchText: String? = nil,
        pbsOnly: Bool = false,
        durationMin: TimeInterval? = nil,
        durationMax: TimeInterval? = nil,
        sort: WorkoutSortField = .date,
        dir: SortDir = .desc
    ) {
        self.sport = sport
        self.workoutType = workoutType
        self.dateFrom = dateFrom
        self.dateTo = dateTo
        self.distanceM = distanceM
        self.hasStroke = hasStroke
        self.searchText = searchText
        self.pbsOnly = pbsOnly
        self.durationMin = durationMin
        self.durationMax = durationMax
        self.sort = sort
        self.dir = dir
    }

    /// Whether any filter beyond sort is active.
    public var isFiltered: Bool {
        sport != nil
            || workoutType != nil
            || dateFrom != nil
            || dateTo != nil
            || distanceM != nil
            || hasStroke != nil
            || !(searchText ?? "").isEmpty
            || pbsOnly
            || durationMin != nil
            || durationMax != nil
    }
}

// MARK: - Chip Constants

public enum WorkoutChips {
    /// Standard distance chip nominal metres with ±2% tolerance.
    public static let distanceChips: [(metres: Double, label: String)] = [
        (500, "500m"),
        (2_000, "2k"),
        (5_000, "5k"),
        (10_000, "10k"),
        (42_195, "Marathon"),
    ]

    /// Standard duration chip seconds with ±10% tolerance.
    public static let durationChips: [(seconds: TimeInterval, label: String)] = [
        (1_200, "20 min"),
        (1_800, "30 min"),
        (3_600, "60 min"),
    ]
}

// MARK: - Query Engine

public enum WorkoutQuery {
    // MARK: Filter + Sort

    /// Filter and sort workouts according to the query. Pure, testable.
    public static func filterAndSortWorkouts(
        _ workouts: [Workout],
        query: WorkoutListQuery,
        pbIds: Set<Int>? = nil
    ) -> [Workout] {
        let pbs: Set<Int>? = if query.pbsOnly {
            pbIds ?? pbWorkoutIds(workouts: workouts, sport: query.sport)
        } else {
            nil
        }

        let filtered = workouts.filter { w in
            if let sport = query.sport, w.sport != sport { return false }
            if let wt = query.workoutType, w.workoutType != wt { return false }
            if query.dateFrom != nil || query.dateTo != nil {
                let dayKey = RowPlayDateTime.dayKeyFromDate(w.date)
                if let from = query.dateFrom, dayKey < from { return false }
                if let to = query.dateTo, dayKey > to { return false }
            }
            if let nominal = query.distanceM {
                if abs(w.distance - nominal) > nominal * 0.02 { return false }
            }
            if let hasStroke = query.hasStroke {
                if hasStroke && !w.hasStrokeData { return false }
                if !hasStroke && w.hasStrokeData { return false }
            }
            if let rawText = query.searchText {
                let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { return true }
                let match = w.workoutType.localizedCaseInsensitiveContains(text)
                    || w.sport.displayName.localizedCaseInsensitiveContains(text)
                    || (w.comments?.localizedCaseInsensitiveContains(text) ?? false)
                    || (w.source?.localizedCaseInsensitiveContains(text) ?? false)
                if !match { return false }
            }
            if query.pbsOnly, let pbs, !pbs.contains(w.id) { return false }
            if let dMin = query.durationMin, w.time < dMin { return false }
            if let dMax = query.durationMax, w.time > dMax { return false }
            return true
        }

        let ascending = query.dir == .asc
        return filtered.sorted { a, b in
            var cmp: Bool
            switch query.sort {
            case .date:
                cmp = ascending ? a.date < b.date : a.date > b.date
            case .distance:
                cmp = ascending ? a.distance < b.distance : a.distance > b.distance
            case .time:
                cmp = ascending ? a.time < b.time : a.time > b.time
            case .pace:
                let pa = a.pace > 0 ? a.pace : (ascending ? .infinity : -1)
                let pb = b.pace > 0 ? b.pace : (ascending ? .infinity : -1)
                if pa != pb {
                    cmp = ascending ? pa < pb : pa > pb
                } else {
                    cmp = ascending ? a.date < b.date : a.date > b.date
                }
            case .power:
                let pa = avgPowerWatts(for: a) ?? (ascending ? .infinity : -1)
                let pb = avgPowerWatts(for: b) ?? (ascending ? .infinity : -1)
                if pa != pb {
                    cmp = ascending ? pa < pb : pa > pb
                } else {
                    cmp = ascending ? a.date < b.date : a.date > b.date
                }
            }
            return cmp
        }
    }

    // MARK: Chip Toggles

    /// Toggle a distance chip on/off, clearing duration chips.
    public static func toggleDistanceChip(_ query: WorkoutListQuery, metres: Double) -> WorkoutListQuery {
        var q = query
        let isOn = q.distanceM == metres
        q.distanceM = isOn ? nil : metres
        q.durationMin = nil
        q.durationMax = nil
        return q
    }

    /// Toggle a duration chip on/off, clearing distance chips.
    public static func toggleDurationChip(_ query: WorkoutListQuery, seconds: TimeInterval) -> WorkoutListQuery {
        var q = query
        let tol = seconds * 0.1
        let isOn = q.durationMin == seconds - tol && q.durationMax == seconds + tol
        q.durationMin = isOn ? nil : seconds - tol
        q.durationMax = isOn ? nil : seconds + tol
        q.distanceM = nil
        return q
    }

    /// Whether a duration chip is currently active.
    public static func durationChipActive(_ query: WorkoutListQuery, seconds: TimeInterval) -> Bool {
        let tol = seconds * 0.1
        return query.durationMin == seconds - tol && query.durationMax == seconds + tol
    }

    // MARK: Helpers

    /// Average watts for a workout.
    public static func avgPowerWatts(for workout: Workout) -> Double? {
        guard let wm = workout.wattMinutes, workout.time > 0 else { return nil }
        return (wm * 60) / workout.time
    }

    /// Workout IDs that hold a PB at any standard distance, optionally filtered by sport.
    public static func pbWorkoutIds(workouts: [Workout], sport: Sport? = nil) -> Set<Int> {
        PersonalBests.pbWorkoutIds(for: workouts, sport: sport)
    }

    /// Create a default query (sort by date, descending).
    public static var defaultQuery: WorkoutListQuery {
        WorkoutListQuery()
    }

    /// Clear all filters, preserving sort.
    public static func clearFilters(_ query: WorkoutListQuery) -> WorkoutListQuery {
        WorkoutListQuery(sort: query.sort, dir: query.dir)
    }
}
