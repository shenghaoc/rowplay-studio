/// User-selected ceiling for the RealityKit replay's rendering budget.
///
/// Adaptive quality may move down from the selected tier for the lifetime of a
/// replay scene, but it never moves above this ceiling or upgrades by itself.
public enum ReplayRenderQuality: String, CaseIterable, Equatable, Sendable {
    case low
    case medium
    case high
    case ultra

    public static let defaultQuality: ReplayRenderQuality = .medium

    public var configuration: ReplayRenderConfiguration {
        switch self {
        case .low:
            ReplayRenderConfiguration(
                courseRingSegmentCount: 48,
                laneMarkerCount: 24,
                wakeEntryCapacityPerParticipant: 0,
                sprayParticleCapacity: 0,
                sprayDropletsPerSidePerCatch: 0,
                targetFrameRate: 30
            )
        case .medium:
            ReplayRenderConfiguration(
                courseRingSegmentCount: 72,
                laneMarkerCount: 48,
                wakeEntryCapacityPerParticipant: 16,
                sprayParticleCapacity: 40,
                sprayDropletsPerSidePerCatch: 4,
                targetFrameRate: 60
            )
        case .high:
            ReplayRenderConfiguration(
                courseRingSegmentCount: 96,
                laneMarkerCount: 64,
                wakeEntryCapacityPerParticipant: 28,
                sprayParticleCapacity: 48,
                sprayDropletsPerSidePerCatch: 4,
                targetFrameRate: 60
            )
        case .ultra:
            ReplayRenderConfiguration(
                courseRingSegmentCount: 144,
                laneMarkerCount: 96,
                wakeEntryCapacityPerParticipant: 44,
                sprayParticleCapacity: 72,
                sprayDropletsPerSidePerCatch: 6,
                targetFrameRate: 60
            )
        }
    }

    /// Number of one-tier degradation steps available below this ceiling.
    public var maximumDegradationLevel: Int {
        switch self {
        case .low: 0
        case .medium: 1
        case .high: 2
        case .ultra: 3
        }
    }

    /// The next lower tier, with low remaining sticky at low.
    public var nextLowerQuality: ReplayRenderQuality {
        switch self {
        case .low: .low
        case .medium: .low
        case .high: .medium
        case .ultra: .high
        }
    }

    /// Apply a sticky degradation level without permitting an upgrade.
    public func degraded(by levels: Int) -> ReplayRenderQuality {
        guard levels > 0 else { return self }
        let boundedLevels = min(levels, maximumDegradationLevel)
        var quality = self
        for _ in 0..<boundedLevels {
            quality = quality.nextLowerQuality
        }
        return quality
    }
}

/// Portable entity and geometry budgets for one replay quality tier.
public struct ReplayRenderConfiguration: Equatable, Sendable {
    public static let maximumCourseRingSegmentCount = 144
    public static let maximumLaneMarkerCount = 96
    public static let maximumWakeEntryCapacityPerParticipant = 44
    public static let maximumSprayParticleCapacity = 72
    public static let maximumSprayDropletsPerSidePerCatch = 6

    public let courseRingSegmentCount: Int
    public let laneMarkerCount: Int
    public let wakeEntryCapacityPerParticipant: Int
    public let sprayParticleCapacity: Int
    public let sprayDropletsPerSidePerCatch: Int
    public let targetFrameRate: Int

    public init(
        courseRingSegmentCount: Int,
        laneMarkerCount: Int,
        wakeEntryCapacityPerParticipant: Int,
        sprayParticleCapacity: Int,
        sprayDropletsPerSidePerCatch: Int,
        targetFrameRate: Int
    ) {
        self.courseRingSegmentCount = Self.bounded(
            courseRingSegmentCount,
            maximum: Self.maximumCourseRingSegmentCount
        )
        self.laneMarkerCount = Self.bounded(
            laneMarkerCount,
            maximum: Self.maximumLaneMarkerCount
        )
        self.wakeEntryCapacityPerParticipant = Self.bounded(
            wakeEntryCapacityPerParticipant,
            maximum: Self.maximumWakeEntryCapacityPerParticipant
        )
        self.sprayParticleCapacity = Self.bounded(
            sprayParticleCapacity,
            maximum: Self.maximumSprayParticleCapacity
        )
        self.sprayDropletsPerSidePerCatch = Self.bounded(
            sprayDropletsPerSidePerCatch,
            maximum: Self.maximumSprayDropletsPerSidePerCatch
        )
        self.targetFrameRate = targetFrameRate == 30 ? 30 : 60
    }

    private static func bounded(_ value: Int, maximum: Int) -> Int {
        min(maximum, max(0, value))
    }
}
