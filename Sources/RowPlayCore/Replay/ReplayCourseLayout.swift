import Foundation

/// Renderer-neutral 3D position as a simple tuple of doubles.
/// No SIMD or platform-specific types so it stays portable in RowPlayCore.
public typealias ReplayPosition = (x: Double, y: Double, z: Double)

/// Deterministic 400-metre circular course layout.
///
/// The live participant travels around a loop at `loopRadius`; the ghost
/// travels at `ghostRadius`. All coordinates are renderer-neutral.
public struct ReplayCourseLayout: Equatable, Sendable {
    /// Total loop length in metres (one lap).
    public static let loopMeters: Double = 400

    /// Radius of the live participant's lane (metres).
    public let loopRadius: Double
    /// Radius of the ghost lane (metres).
    public let ghostRadius: Double

    /// Default layout with standard radii.
    public static let standard = ReplayCourseLayout(loopRadius: 63.66, ghostRadius: 57.29)

    public init(loopRadius: Double, ghostRadius: Double) {
        self.loopRadius = max(1.0, loopRadius)
        self.ghostRadius = max(1.0, ghostRadius)
    }

    /// Position on the course at the given distance (metres) and lane offset.
    ///
    /// - Parameters:
    ///   - distance: Cumulative distance in metres. Wraps correctly for
    ///     multiple laps. Negative values produce valid positions.
    ///   - laneOffset: Lateral offset in metres from the lane center.
    ///     Positive = outward, negative = inward.
    /// - Returns: `(x, y, z)` position. Y is always 0 (ground plane).
    public func position(at distance: Double, laneOffset: Double = 0) -> ReplayPosition {
        let safeDistance = finite(distance, fallback: 0)
        let safeOffset = finite(laneOffset, fallback: 0)
        let angle = loopAngle(for: safeDistance)
        let radius = loopRadius + safeOffset
        return (
            x: radius * sin(angle),
            y: 0,
            z: radius * cos(angle)
        )
    }

    /// Position for the ghost lane at the given distance.
    public func ghostPosition(at distance: Double, laneOffset: Double = 0) -> ReplayPosition {
        let safeDistance = finite(distance, fallback: 0)
        let safeOffset = finite(laneOffset, fallback: 0)
        let angle = loopAngle(for: safeDistance)
        let radius = ghostRadius + safeOffset
        return (
            x: radius * sin(angle),
            y: 0,
            z: radius * cos(angle)
        )
    }

    /// Unit tangent direction at the given distance (direction of travel).
    public func tangent(at distance: Double) -> ReplayPosition {
        let safeDistance = finite(distance, fallback: 0)
        let angle = loopAngle(for: safeDistance)
        // Tangent is perpendicular to the radial direction.
        return (x: cos(angle), y: 0, z: -sin(angle))
    }

    /// Y-axis heading angle (radians) for an entity facing the direction of
    /// travel at the given distance.
    public func headingAngle(at distance: Double) -> Double {
        let t = tangent(at: distance)
        return atan2(t.x, t.z)
    }

    /// Convert cumulative distance to an angle on the loop.
    /// Uses modular arithmetic so multiple laps wrap naturally.
    public func loopAngle(for distance: Double) -> Double {
        let safeDistance = finite(distance, fallback: 0)
        return (safeDistance / Self.loopMeters) * Double.pi * 2
    }

    /// Total number of laps for the given workout distance.
    public func lapCount(for totalDistance: Double) -> Int {
        let safeDistance = finite(totalDistance, fallback: 0)
        let raw = ceil(safeDistance / Self.loopMeters)
        guard raw < Double(Int.max - 1) else { return Int.max }
        return max(1, Int(raw))
    }

    /// Current lap number (1-based) for the given distance.
    public func currentLap(for distance: Double) -> Int {
        let safeDistance = max(0, finite(distance, fallback: 0))
        let raw = safeDistance / Self.loopMeters
        guard raw < Double(Int.max - 2) else { return lapCount(for: safeDistance) }
        let laps = Int(raw) + 1
        return min(laps, lapCount(for: safeDistance))
    }
}

// MARK: - Private

private func finite(_ v: Double, fallback: Double) -> Double {
    v.isFinite ? v : fallback
}
