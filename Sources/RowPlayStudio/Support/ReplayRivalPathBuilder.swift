import CoreGraphics
import RowPlayCore
import SwiftUI

/// Builds the cached, visual-only 2D rival trace without changing the full
/// stroke data used by replay sampling and race-result calculations.
enum ReplayRivalPathBuilder {
    struct Sample: Equatable, Sendable {
        let elapsed: TimeInterval
        let distance: Double
    }

    /// Produces samples over exactly the player's duration. Longer traces are
    /// interpolated at the cutoff; shorter traces hold their final distance.
    /// Dense traces are decimated while preserving both endpoints.
    static func samples(
        ghostStrokes: [Stroke],
        playerDuration: TimeInterval,
        maximumPointCount: Int
    ) -> [Sample] {
        guard ghostStrokes.count > 1,
              playerDuration.isFinite,
              playerDuration > 0,
              maximumPointCount >= 2 else {
            return []
        }

        let ghostOriginT = ghostStrokes[0].t
        let targetT = ghostOriginT + playerDuration
        guard ghostOriginT.isFinite, targetT.isFinite else { return [] }

        let endpoint = ReplaySample.sampleAt(strokes: ghostStrokes, t: targetT)
        guard endpoint.d.isFinite else { return [] }

        // Find the first source stroke at or beyond the player's finish. The
        // conceptual sequence is every earlier source stroke plus one exact
        // endpoint, which ReplaySample either interpolates or holds.
        var low = 0
        var high = ghostStrokes.count
        while low < high {
            let middle = low + (high - low) / 2
            if ghostStrokes[middle].t < targetT {
                low = middle + 1
            } else {
                high = middle
            }
        }
        let sourceCount = low
        guard sourceCount > 0 else { return [] }
        let conceptualCount = sourceCount + 1
        let outputCount = min(conceptualCount, maximumPointCount)

        return (0..<outputCount).compactMap { outputIndex in
            let conceptualIndex: Int
            if outputCount == conceptualCount {
                conceptualIndex = outputIndex
            } else {
                let position = Double(outputIndex) * Double(conceptualCount - 1)
                    / Double(outputCount - 1)
                conceptualIndex = Int(position.rounded())
            }
            if conceptualIndex == sourceCount {
                return Sample(elapsed: playerDuration, distance: endpoint.d)
            }
            let stroke = ghostStrokes[conceptualIndex]
            let elapsed = stroke.t - ghostOriginT
            guard elapsed.isFinite, elapsed >= 0, stroke.d.isFinite else { return nil }
            return Sample(elapsed: elapsed, distance: stroke.d)
        }
    }

    static func pointLimit(for size: CGSize) -> Int {
        guard size.width.isFinite else { return 2 }
        // One point per horizontal point is enough for a visual polyline, and
        // the fixed ceiling bounds very large or dense imported traces.
        let cappedWidth = min(max(size.width, 1), 2_047)
        return Int(cappedWidth.rounded(.up)) + 1
    }

    static func makePath(
        ghostStrokes: [Stroke],
        playerStrokes: [Stroke],
        size: CGSize
    ) -> Path {
        guard ghostStrokes.count > 1,
              playerStrokes.count > 1,
              size.width.isFinite,
              size.width > 0,
              size.height.isFinite,
              size.height > 0 else {
            return Path()
        }

        let playerOriginT = playerStrokes[0].t
        let maxT = playerStrokes.last?.t ?? playerOriginT
        let maxD = playerStrokes.last?.d ?? 1
        let duration = maxT - playerOriginT
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return Path() }

        let pathSamples = samples(
            ghostStrokes: ghostStrokes,
            playerDuration: duration,
            maximumPointCount: pointLimit(for: size)
        )
        guard !pathSamples.isEmpty else { return Path() }

        var path = Path()
        for (index, sample) in pathSamples.enumerated() {
            let x = unitFraction(sample.elapsed, denominator: duration) * size.width
            let y = size.height - unitFraction(sample.distance, denominator: maxD) * size.height
            let point = CGPoint(
                x: max(0, min(size.width, x)),
                y: max(0, min(size.height, y))
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }

    private static func unitFraction(_ numerator: Double, denominator: Double) -> CGFloat {
        guard numerator.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return CGFloat(max(0, min(1, numerator / denominator)))
    }
}
