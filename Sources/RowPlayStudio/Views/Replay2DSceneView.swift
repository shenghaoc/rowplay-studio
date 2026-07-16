import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

/// Timeline/canvas rendering for the lightweight 2D replay mode.
struct Replay2DSceneView: View {
    let detail: WorkoutDetail
    @Binding var state: ReplayState
    let rival: ReplayRival?
    let distanceUnit: DistanceUnit
    let reduceMotion: Bool
    let contentRevision: UInt64

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastTickDate: Date?
    @State private var strokePath = Path()
    @State private var ghostStrokePath = Path()
    @State private var canvasSize: CGSize = .zero
    @State private var cachedMachineColor: Color = .accentColor

    var body: some View {
        let interval = reduceMotion ? 1.0 / 15.0 : 1.0 / 60.0
        TimelineView(.animation(minimumInterval: interval, paused: !state.playing)) { timelineContext in
            replayCanvas
                .onChange(of: timelineContext.date) { _, newDate in
                    guard state.playing else {
                        lastTickDate = newDate
                        return
                    }
                    let tick = ReplayPlaybackClock.tick(
                        lastTickDate: lastTickDate,
                        currentDate: newDate
                    )
                    lastTickDate = tick.lastTickDate
                    state.tick(deltaTime: tick.delta)
                }
        }
        .frame(minHeight: 300)
        .onChange(of: state.playing) { _, playing in
            if playing {
                lastTickDate = nil
            }
        }
        .onChange(of: rival?.id) { _, _ in
            rebuildGhostPath()
        }
        .onChange(of: detail.id) { _, _ in
            rebuildPaths()
        }
        .onChange(of: contentRevision) { _, _ in
            rebuildPaths()
        }
    }

    private var replayCanvas: some View {
        Canvas { context, size in
            context.stroke(
                ghostStrokePath,
                with: .color(AppDesign.softPurple.opacity(0.35)),
                lineWidth: 1.5
            )
            context.stroke(
                strokePath,
                with: .color(cachedMachineColor.opacity(0.7)),
                lineWidth: 2
            )
            drawGhostPlayhead(in: &context, size: size)
            drawPlayhead(in: &context, size: size)
        }
        .accessibilityLabel("Workout replay timeline")
        .accessibilityValue(canvasAccessibilityValue)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size, initial: true) { _, newSize in
                        canvasSize = newSize
                        rebuildPaths()
                    }
            }
        )
        .onAppear {
            cachedMachineColor = ReplayView.machineColor(
                for: detail.workout.sport,
                colorScheme: colorScheme
            )
        }
        .onChange(of: colorScheme) { _, scheme in
            cachedMachineColor = ReplayView.machineColor(
                for: detail.workout.sport,
                colorScheme: scheme
            )
        }
    }

    private func rebuildPaths() {
        strokePath = Self.makeStrokePath(strokes: detail.strokes, size: canvasSize)
        cachedMachineColor = ReplayView.machineColor(
            for: detail.workout.sport,
            colorScheme: colorScheme
        )
        rebuildGhostPath()
    }

    private func rebuildGhostPath() {
        guard canvasSize != .zero, let rival else {
            ghostStrokePath = Path()
            return
        }
        ghostStrokePath = Self.makeGhostStrokePath(
            ghostStrokes: rival.strokes,
            playerStrokes: detail.strokes,
            size: canvasSize
        )
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        let duration = state.duration
        let maximumDistance = detail.strokes.last?.d ?? 1
        guard duration.isFinite,
              duration > 0,
              maximumDistance.isFinite,
              maximumDistance > 0 else {
            return
        }
        let frame = state.currentFrame
        let x = Self.unitFraction(frame.t, denominator: duration) * size.width
        let y = size.height - Self.unitFraction(
            frame.d,
            denominator: maximumDistance
        ) * size.height

        var playhead = Path()
        playhead.move(to: CGPoint(x: x, y: 0))
        playhead.addLine(to: CGPoint(x: x, y: size.height))
        let playheadColor = AppDesign.alertRed
        context.stroke(playhead, with: .color(playheadColor), lineWidth: 1)

        let dotSize: CGFloat = 8
        let dot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2,
            y: y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        context.fill(dot, with: .color(playheadColor))
    }

    private func drawGhostPlayhead(in context: inout GraphicsContext, size: CGSize) {
        guard let rival, !rival.strokes.isEmpty else { return }
        let duration = state.duration
        let maximumDistance = detail.strokes.last?.d ?? 1
        guard duration.isFinite,
              duration > 0,
              maximumDistance.isFinite,
              maximumDistance > 0 else {
            return
        }

        let ghostDistance = ReplayRaceGap.ghostDistance(
            elapsed: state.time,
            strokes: rival.strokes
        )
        guard ghostDistance.isFinite, ghostDistance >= 0 else { return }

        let x = Self.unitFraction(state.time, denominator: duration) * size.width
        let y = size.height - Self.unitFraction(
            ghostDistance,
            denominator: maximumDistance
        ) * size.height

        let ghostColor = AppDesign.softPurple
        let dotSize: CGFloat = 8
        let dot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2,
            y: y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        let strokeDot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2 - 1,
            y: y - dotSize / 2 - 1,
            width: dotSize + 2,
            height: dotSize + 2
        ))
        context.stroke(
            strokeDot,
            with: .color(cachedMachineColor.opacity(0.3)),
            lineWidth: 1
        )
        context.fill(dot, with: .color(ghostColor.opacity(0.8)))
    }

    private var canvasAccessibilityValue: String {
        let frame = state.currentFrame
        var parts = [
            "Time \(RowPlayFormatting.time(frame.t, tenths: true))",
            "Distance \(RowPlayFormatting.distance(frame.d, unit: distanceUnit))"
        ]
        if let rival {
            let ghostDistance = ReplayRaceGap.ghostDistance(
                elapsed: state.time,
                strokes: rival.strokes
            )
            let gapMeters = ReplayRaceGap.raceGapMeters(
                playerDistance: frame.d,
                ghostDistance: ghostDistance
            )
            parts.append(ReplayRivalGapFormatting.metersLabel(gapMeters, unit: distanceUnit))
        }
        return parts.joined(separator: ", ")
    }

    static func makeStrokePath(strokes: [Stroke], size: CGSize) -> Path {
        guard strokes.count > 1 else { return Path() }

        let originTime = strokes[0].t
        let maximumTime = strokes.last?.t ?? originTime
        let maximumDistance = strokes.last?.d ?? 1
        let duration = maximumTime - originTime
        guard duration.isFinite,
              duration > 0,
              maximumDistance.isFinite,
              maximumDistance > 0 else {
            return Path()
        }

        var path = Path()
        for (index, stroke) in strokes.enumerated() {
            let x = unitFraction(stroke.t - originTime, denominator: duration) * size.width
            let y = size.height - unitFraction(
                stroke.d,
                denominator: maximumDistance
            ) * size.height
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    static func makeGhostStrokePath(
        ghostStrokes: [Stroke],
        playerStrokes: [Stroke],
        size: CGSize
    ) -> Path {
        ReplayRivalPathBuilder.makePath(
            ghostStrokes: ghostStrokes,
            playerStrokes: playerStrokes,
            size: size
        )
    }

    private static func unitFraction(_ numerator: Double, denominator: Double) -> CGFloat {
        guard numerator.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return CGFloat(max(0, min(1, numerator / denominator)))
    }
}
