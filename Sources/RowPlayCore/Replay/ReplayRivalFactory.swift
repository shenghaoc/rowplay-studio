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
        // Include a content fingerprint so a library refresh of the same workout
        // ID rebuilds SwiftUI/RealityKit identity and cached race artifacts.
        let id = "session-\(detail.workout.id)-\(Self.traceIdentity(for: strokes))"
        return ReplayRival(
            id: id,
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
        guard isValidPositiveFinite(pacePer500m),
              Int(exactly: pacePer500m.rounded()) != nil else {
            return nil
        }
        let resolvedSport = sport ?? player.sport
        let axis = ComparabilityGuard.classifyAxis(workoutType: player.workoutType)
        let paceLabel = Self.paceLabel(pacePer500m)

        switch axis {
        case .distance:
            let distance = player.distance
            guard isValidPositiveFinite(distance) else { return nil }
            let totalTime = (distance / 500.0) * pacePer500m
            guard isValidPositiveFinite(totalTime), totalTime < 1e12 else { return nil }
            guard let watts = Self.safeWatts(for: resolvedSport, pacePer500m: pacePer500m) else {
                return nil
            }
            let strokes = twoPointTrace(
                endTime: totalTime,
                endDistance: distance,
                pace: pacePer500m,
                watts: watts
            )
            return ReplayRival(
                id: "pace-\(Self.stableDoubleKey(pacePer500m))-d-\(Self.stableDoubleKey(distance))",
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
            guard let watts = Self.safeWatts(for: resolvedSport, pacePer500m: pacePer500m) else {
                return nil
            }
            let strokes = twoPointTrace(
                endTime: duration,
                endDistance: distance,
                pace: pacePer500m,
                watts: watts
            )
            return ReplayRival(
                id: "pace-\(Self.stableDoubleKey(pacePer500m))-t-\(Self.stableDoubleKey(duration))",
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
        guard let watts = safeWatts(for: sport, pacePer500m: pacePer500m) else { return [] }
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
        let lastComponent = fileName.map(ReplayPathUtilities.lastPathComponent).flatMap { $0.isEmpty ? nil : $0 }
        let label = lastComponent ?? "Imported rival"
        let sourceKey = lastComponent.map(Self.stableStringKey) ?? "anonymous"
        // Include the normalized trace so replacing a same-named file refreshes
        // SwiftUI/RealityKit identity and every derived race/share artifact.
        let idSuffix = "\(sourceKey)-\(Self.traceIdentity(for: strokes))"
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

    private static func safeWatts(for sport: Sport, pacePer500m: TimeInterval) -> Int? {
        let watts = RowPlayFormatting.paceToWatts(for: sport, pacePer500m: pacePer500m)
        guard watts.isFinite, watts > 0,
              let roundedWatts = Int(exactly: watts.rounded()),
              roundedWatts > 0 else {
            return nil
        }
        return roundedWatts
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

    private static func stableDoubleKey(_ value: Double) -> String {
        // Every accepted value is finite and positive, so its IEEE 754 bit
        // pattern is an exact, deterministic identity without decimal rounding.
        String(value.bitPattern, radix: 16)
    }

    private static func stableStringKey(_ value: String) -> String {
        // Deterministic short fingerprint without leaking the full path.
        var hash: UInt64 = 5381
        for unit in value.utf8 {
            hash = ((hash &<< 5) &+ hash) &+ UInt64(unit)
        }
        return String(hash, radix: 16)
    }

    /// Exact deterministic identity for a normalized replay trace. UI owners
    /// use this to reset all playback-derived state when a same-ID workout's
    /// stroke content changes after a library refresh.
    public static func traceIdentity(for strokes: [Stroke]) -> String {
        // Fixed FNV-1a over numeric bit patterns. Swift's Hasher is deliberately
        // randomized and therefore unsuitable for stable view identity.
        var hash: UInt64 = 14_695_981_039_346_656_037
        let prime: UInt64 = 1_099_511_628_211

        func mix(_ value: UInt64) {
            for shift in stride(from: 0, through: 56, by: 8) {
                hash ^= (value >> UInt64(shift)) & 0xFF
                hash &*= prime
            }
        }

        mix(UInt64(strokes.count))
        for stroke in strokes {
            mix(stroke.t.bitPattern)
            mix(stroke.d.bitPattern)
            mix(stroke.pace.bitPattern)
            mix(stroke.cadence.bitPattern)
            mix(stroke.heartRate.map { UInt64(bitPattern: Int64($0)) } ?? UInt64.max)
            mix(UInt64(bitPattern: Int64(stroke.watts)))
        }
        return String(hash, radix: 16)
    }
}

/// Race-defining identity for the primary replay workout. Constructing it is
/// O(N) in the stroke count, so platform state caches it when workout details
/// change and SwiftUI only performs an O(1) lookup during body evaluation.
public struct ReplayPrimaryContentIdentity: Hashable, Sendable {
    public let workoutID: Int
    public let traceIdentity: String
    public let sportRawValue: String
    public let workoutType: String
    public let targetDistanceBits: UInt64
    public let targetDurationBits: UInt64

    public init(detail: WorkoutDetail) {
        workoutID = detail.id
        traceIdentity = ReplayRivalFactory.traceIdentity(for: detail.strokes)
        sportRawValue = detail.workout.sport.rawValue
        workoutType = detail.workout.workoutType
        targetDistanceBits = detail.workout.distance.bitPattern
        targetDurationBits = detail.workout.time.bitPattern
    }
}
