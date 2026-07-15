import Foundation

/// Builds portable ``ReplayRival`` values for past-session, constant-pace, and imported traces.
public enum ReplayRivalFactory: Sendable {

    // MARK: - Past session

    /// Convert a past-session workout detail into a rival.
    ///
    /// Requires at least two strokes. Marks the rival as genuine stroke data.
    public static func makeSessionRival(from detail: WorkoutDetail) -> ReplayRival? {
        let strokes = detail.strokes
        guard strokes.count >= 2 else { return nil }
        let dateLabel = Self.sessionDateLabel(detail.workout.date)
        return ReplayRival(
            id: "session-\(detail.workout.id)",
            kind: .session,
            displayLabel: dateLabel,
            strokes: strokes,
            hasGenuineStrokeData: detail.workout.hasStrokeData && strokes.count >= 2,
            sessionWorkoutID: detail.workout.id
        )
    }

    // MARK: - Constant pace

    /// Create a constant-pace rival for the player's workout axis.
    ///
    /// - Distance-axis: pace boat finishes at the player's target distance.
    /// - Time-axis: pace boat runs for the player's target duration and derives final distance.
    ///
    /// Uses exactly two samples because ``ReplaySample`` interpolates.
    /// Returns `nil` for zero, negative, NaN, infinite, or overflowing inputs.
    public static func makeConstantPaceRival(
        pacePer500m: TimeInterval,
        player: Workout,
        sport: Sport? = nil
    ) -> ReplayRival? {
        guard isValidPositiveFinite(pacePer500m) else { return nil }
        let resolvedSport = sport ?? player.sport
        let axis = ComparabilityGuard.classifyAxis(workoutType: player.workoutType)
        let paceLabel = Self.paceLabel(pacePer500m)

        switch axis {
        case .distance:
            let distance = player.distance
            guard isValidPositiveFinite(distance) else { return nil }
            let totalTime = (distance / 500.0) * pacePer500m
            guard isValidPositiveFinite(totalTime), totalTime < 1e12 else { return nil }
            let watts = Self.safeWatts(for: resolvedSport, pacePer500m: pacePer500m)
            let strokes = twoPointTrace(
                endTime: totalTime,
                endDistance: distance,
                pace: pacePer500m,
                watts: watts
            )
            return ReplayRival(
                id: "pace-\(Self.stablePaceKey(pacePer500m))-d-\(Self.stableDistanceKey(distance))",
                kind: .constantPace,
                displayLabel: paceLabel,
                strokes: strokes,
                hasGenuineStrokeData: false,
                targetPace: pacePer500m
            )

        case .time:
            let duration = player.time
            guard isValidPositiveFinite(duration) else { return nil }
            // distance = 500 * duration / pace
            let distance = (500.0 * duration) / pacePer500m
            guard isValidPositiveFinite(distance), distance < 1e12 else { return nil }
            let watts = Self.safeWatts(for: resolvedSport, pacePer500m: pacePer500m)
            let strokes = twoPointTrace(
                endTime: duration,
                endDistance: distance,
                pace: pacePer500m,
                watts: watts
            )
            return ReplayRival(
                id: "pace-\(Self.stablePaceKey(pacePer500m))-t-\(Self.stableTimeKey(duration))",
                kind: .constantPace,
                displayLabel: paceLabel,
                strokes: strokes,
                hasGenuineStrokeData: false,
                targetPace: pacePer500m
            )
        }
    }

    /// Convenience matching web `constantPaceGhost` for distance-axis pieces.
    public static func constantPaceStrokes(
        pacePer500m: TimeInterval,
        totalDistance: Double,
        sport: Sport = .rower
    ) -> [Stroke] {
        guard isValidPositiveFinite(pacePer500m), isValidPositiveFinite(totalDistance) else {
            return []
        }
        let totalTime = (totalDistance / 500.0) * pacePer500m
        guard isValidPositiveFinite(totalTime), totalTime < 1e12 else { return [] }
        let watts = safeWatts(for: sport, pacePer500m: pacePer500m)
        return twoPointTrace(
            endTime: totalTime,
            endDistance: totalDistance,
            pace: pacePer500m,
            watts: watts
        )
    }

    // MARK: - Imported file

    /// Convert a parsed imported trace into a rival.
    ///
    /// Imported rivals are not genuine Concept2 stroke traces.
    public static func makeImportedRival(
        strokes: [Stroke],
        fileName: String?
    ) -> ReplayRival? {
        guard strokes.count >= 2 else { return nil }
        let lastComponent = fileName.map(Self.lastPathComponent).flatMap { $0.isEmpty ? nil : $0 }
        let label = lastComponent ?? "Imported rival"
        let idSuffix = lastComponent.map { Self.stableStringKey($0) } ?? UUID().uuidString
        return ReplayRival(
            id: "file-\(idSuffix)",
            kind: .importedFile,
            displayLabel: label,
            strokes: strokes,
            hasGenuineStrokeData: false,
            localFileName: lastComponent
        )
    }

    // MARK: - Helpers

    private static func twoPointTrace(
        endTime: TimeInterval,
        endDistance: Double,
        pace: TimeInterval,
        watts: Int
    ) -> [Stroke] {
        [
            Stroke(t: 0, d: 0, pace: pace, cadence: 0, watts: watts),
            Stroke(t: endTime, d: endDistance, pace: pace, cadence: 0, watts: watts),
        ]
    }

    private static func safeWatts(for sport: Sport, pacePer500m: TimeInterval) -> Int {
        let watts = RowPlayFormatting.paceToWatts(for: sport, pacePer500m: pacePer500m)
        guard watts.isFinite, watts > 0, watts <= Double(Int.max) else { return 0 }
        return Int(watts.rounded())
    }

    private static func isValidPositiveFinite(_ value: Double) -> Bool {
        value.isFinite && value > 0
    }

    private static func paceLabel(_ pace: TimeInterval) -> String {
        let formatted = PaceInput.formatPaceInput(pace)
        if formatted.isEmpty {
            return RowPlayFormatting.pace(pace)
        }
        return "\(formatted)/500m"
    }

    private static func sessionDateLabel(_ date: Date) -> String {
        // Locale-independent stable label for identity/export contexts.
        // UI layers reformat with the user's locale.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        return formatter.string(from: date)
    }

    private static func lastPathComponent(_ path: String) -> String {
        // Accept both POSIX and display-style paths without Foundation URL parsing.
        if let slash = path.lastIndex(of: "/") {
            return String(path[path.index(after: slash)...])
        }
        if let slash = path.lastIndex(of: "\\") {
            return String(path[path.index(after: slash)...])
        }
        return path
    }

    private static func stablePaceKey(_ pace: TimeInterval) -> String {
        String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), pace)
    }

    private static func stableDistanceKey(_ distance: Double) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), distance)
    }

    private static func stableTimeKey(_ time: TimeInterval) -> String {
        String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), time)
    }

    private static func stableStringKey(_ value: String) -> String {
        // Deterministic short fingerprint without leaking the full path.
        var hash: UInt64 = 5381
        for unit in value.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(unit)
        }
        return String(hash, radix: 16)
    }
}
