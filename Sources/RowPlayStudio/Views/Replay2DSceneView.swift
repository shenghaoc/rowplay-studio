import CoreGraphics
import Foundation
import RowPlayCore
import SwiftUI

private enum Replay2DParticipantKinematics {
    case rower(ReplayRowerKinematics)
    case skierg(ReplaySkierKinematics)
    case bike(ReplayBikeKinematics)

    static func solve(sport: Sport, pose: ReplayStrokePose) -> Self {
        switch sport {
        case .rower: .rower(ReplaySportKinematics.solveRower(pose))
        case .skierg: .skierg(ReplaySportKinematics.solveSkier(pose))
        case .bike: .bike(ReplaySportKinematics.solveBike(pose))
        }
    }
}

/// Sport-authentic Canvas replay. Time and distance remain visible as a
/// secondary HUD while the venue and articulated participants carry the scene.
struct Replay2DSceneView: View {
    let detail: WorkoutDetail
    @Binding var state: ReplayState
    let rival: ReplayRival?
    let distanceUnit: DistanceUnit
    let reduceMotion: Bool
    let contentRevision: UInt64

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastTickDate: Date?
    @State private var livePoseContext: ReplayStrokePoseContext?
    @State private var liveMedianHR = 0
    @State private var rivalPoseContext: ReplayStrokePoseContext?
    @State private var rivalMedianHR = 0

    private var sport: Sport { detail.workout.sport }

    var body: some View {
        let interval = reduceMotion ? 1.0 / 15.0 : 1.0 / 60.0
        TimelineView(.animation(minimumInterval: interval, paused: !state.playing)) { timeline in
            replayCanvas
                .onChange(of: timeline.date) { _, date in
                    guard state.playing else {
                        lastTickDate = date
                        return
                    }
                    let tick = ReplayPlaybackClock.tick(
                        lastTickDate: lastTickDate,
                        currentDate: date
                    )
                    lastTickDate = tick.lastTickDate
                    state.tick(deltaTime: tick.delta)
                }
        }
        .frame(minHeight: 300)
        .onAppear(perform: rebuildPoseContexts)
        .onChange(of: state.playing) { _, playing in
            if playing { lastTickDate = nil }
        }
        .onChange(of: detail.id) { _, _ in rebuildPoseContexts() }
        .onChange(of: rival?.id) { _, _ in rebuildPoseContexts() }
        .onChange(of: contentRevision) { _, _ in rebuildPoseContexts() }
    }

    private var replayCanvas: some View {
        Canvas { context, size in
            let frame = state.currentFrame
            let livePose = currentLivePose()
            let ghost = currentGhostSample()
            let colors = Replay2DCanvasColors.palette(darkTheme: colorScheme == .dark)
            let width = Double(size.width)
            let height = Double(size.height)
            let courseY = height * 0.79

            Replay2DEnvironmentRenderer.drawBackground(
                context,
                width: width,
                height: height,
                sport: sport,
                meters: frame.d,
                darkTheme: colorScheme == .dark,
                reduceMotion: reduceMotion
            )

            let liveX = max(Replay2DStyle.padLeading, min(width * 0.62, width - Replay2DStyle.padTrailing))
            let pixelsPerMeter = max(0.12, min(0.7, width / max(500, detail.workout.distance)))
            if let ghostPose = ghost.pose {
                let ghostX = max(
                    Replay2DStyle.padLeading,
                    min(width - Replay2DStyle.padTrailing, liveX + (ghost.distance - frame.d) * pixelsPerMeter)
                )
                drawParticipant(
                    context,
                    pose: ghostPose,
                    x: ghostX,
                    courseY: courseY,
                    meters: ghost.distance,
                    pixelsPerMeter: pixelsPerMeter,
                    accent: colors.ghost,
                    colors: colors,
                    label: "RIVAL",
                    isRival: true
                )
            }
            drawParticipant(
                context,
                pose: livePose,
                x: liveX,
                courseY: courseY,
                meters: frame.d,
                pixelsPerMeter: pixelsPerMeter,
                accent: colors.live,
                colors: colors,
                label: "YOU",
                isRival: false
            )
            drawSecondaryHUD(
                context,
                size: size,
                colors: colors,
                liveDistance: frame.d,
                ghostDistance: ghost.pose == nil ? nil : ghost.distance
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.canvasAccessibilityLabel(for: sport))
        .accessibilityValue(canvasAccessibilityValue)
    }

    private func drawParticipant(
        _ context: GraphicsContext,
        pose: ReplayStrokePose,
        x: Double,
        courseY: Double,
        meters: Double,
        pixelsPerMeter: Double,
        accent: Color,
        colors: Replay2DCanvasColors,
        label: String,
        isRival: Bool
    ) {
        let resolvedPose = reduceMotion ? Replay2DStyle.reducedPose(for: sport) : pose
        let kinematics = Replay2DParticipantKinematics.solve(sport: sport, pose: resolvedPose)
        let surge: Double
        let vertical: Double
        switch kinematics {
        case .rower(let rower):
            surge = reduceMotion ? 0 : rower.surge * Replay2DStyle.surgePixels(for: sport) * resolvedPose.amplitude
            vertical = reduceMotion ? 0 : rower.vertical * Replay2DStyle.bobAmplitude * resolvedPose.amplitude
        case .skierg(let skierg):
            surge = reduceMotion ? 0 : skierg.surge
                * Replay2DStyle.surgePixels(for: sport) * resolvedPose.amplitude
            vertical = 0
        case .bike:
            surge = 0
            vertical = 0
        }

        let figureX = x + surge
        let avatar = Replay2DAvatarContext(
            x: figureX,
            polePlantCourseX: sport == .skierg
                ? Replay2DSkiRenderer.skiPolePlantCourseX2D(
                    currentCourseX: x,
                    pixelsPerMeter: pixelsPerMeter,
                    pose: resolvedPose
                )
                : x,
            y: courseY,
            bobY: courseY + vertical,
            meters: meters,
            accent: accent,
            rim: colors.labelText,
            foam: colors.foam,
            skin: colors.skin,
            skinShade: colors.skinShade,
            hair: colors.hair,
            shoe: colors.shoe,
            reduce: reduceMotion
        )

        var figureContext = context
        figureContext.opacity = isRival ? Replay2DStyle.ghostAvatarAlpha : 1
        figureContext.translateBy(x: figureX, y: courseY)
        figureContext.scaleBy(x: Replay2DStyle.athleteScale, y: Replay2DStyle.athleteScale)
        figureContext.translateBy(x: -figureX, y: -courseY)
        switch kinematics {
        case .rower(let rower):
            Replay2DRowRenderer.draw(
                figureContext,
                avatar: avatar,
                kinematics: rower
            )
        case .skierg(let skierg):
            Replay2DSkiRenderer.draw(
                figureContext,
                avatar: avatar,
                kinematics: skierg
            )
        case .bike(let bike):
            Replay2DBikeRenderer.draw(
                figureContext,
                avatar: avatar,
                kinematics: bike
            )
        }

        let top = courseY - Replay2DStyle.athleteTopClearance(for: sport) * Replay2DStyle.athleteScale
        var labelContext = context
        labelContext.opacity = isRival ? Replay2DStyle.ghostLaneAlpha : 1
        labelContext.draw(
            Text(label).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundStyle(colors.labelText),
            at: CGPoint(x: x, y: max(14, top - 9)),
            anchor: .center
        )
    }

    private func drawSecondaryHUD(
        _ context: GraphicsContext,
        size: CGSize,
        colors: Replay2DCanvasColors,
        liveDistance: Double,
        ghostDistance: Double?
    ) {
        let baselineY = Double(size.height) - 18
        context.stroke(
            Replay2DFigure.linePath(18, baselineY - 10, Double(size.width) - 18, baselineY - 10),
            with: .color(colors.laneLine.opacity(0.55)),
            style: StrokeStyle(lineWidth: 1, dash: [4, 5])
        )
        let left = Text(RowPlayFormatting.time(state.time, tenths: true))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(colors.tickText)
        let right = Text(RowPlayFormatting.distance(liveDistance, unit: distanceUnit))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(colors.tickText)
        context.draw(left, at: CGPoint(x: 20, y: baselineY), anchor: .leading)
        context.draw(right, at: CGPoint(x: size.width - 20, y: baselineY), anchor: .trailing)
        if let ghostDistance {
            let gap = ReplayRaceGap.raceGapMeters(
                playerDistance: liveDistance,
                ghostDistance: ghostDistance
            )
            context.draw(
                Text(ReplayRivalGapFormatting.metersLabel(gap, unit: distanceUnit))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(colors.ghost),
                at: CGPoint(x: size.width / 2, y: baselineY),
                anchor: .center
            )
        }
    }

    private func currentLivePose() -> ReplayStrokePose {
        let frame = state.currentFrame
        let fallback = ReplayStrokePose.fallback(
            sport: sport,
            phase: stablePhase(distance: frame.d),
            rate: frame.cadence
        )
        let initialContext = Self.aggregates(for: detail.strokes, sport: sport).0
        guard let context = livePoseContext ?? initialContext,
              !detail.strokes.isEmpty else { return fallback }
        let absoluteTime = frame.t + (detail.strokes.first?.t ?? 0)
        return pose(
            at: absoluteTime,
            frame: ReplayFrame(
                t: absoluteTime,
                d: frame.d,
                pace: frame.pace,
                cadence: frame.cadence,
                heartRate: frame.heartRate,
                watts: frame.watts,
                progress: frame.progress
            ),
            strokes: detail.strokes,
            context: context,
            medianHR: liveMedianHR,
            duration: state.duration
        ) ?? fallback
    }

    private func currentGhostSample() -> (pose: ReplayStrokePose?, distance: Double) {
        guard let rival, !rival.strokes.isEmpty else { return (nil, 0) }
        let absoluteTime = ReplayRaceGap.absoluteTime(elapsed: state.time, strokes: rival.strokes)
        let frame = ReplaySample.sampleAt(strokes: rival.strokes, t: absoluteTime)
        let fallback = ReplayStrokePose.fallback(
            sport: sport,
            phase: stablePhase(distance: frame.d),
            rate: frame.cadence
        )
        let initialContext = Self.aggregates(for: rival.strokes, sport: sport).0
        guard rival.hasGenuineStrokeData,
              let context = rivalPoseContext ?? initialContext else {
            return (fallback, frame.d)
        }
        let origin = rival.strokes.first?.t ?? 0
        let duration = max(1, (rival.strokes.last?.t ?? origin) - origin)
        return (
            pose(
                at: absoluteTime,
                frame: frame,
                strokes: rival.strokes,
                context: context,
                medianHR: rivalMedianHR,
                duration: duration
            ) ?? fallback,
            frame.d
        )
    }

    private func pose(
        at time: TimeInterval,
        frame: ReplayFrame,
        strokes: [Stroke],
        context: ReplayStrokePoseContext,
        medianHR: Int,
        duration: TimeInterval
    ) -> ReplayStrokePose? {
        let index = ReplaySample.sampleIndexAt(strokes: strokes, t: time)
        guard index >= 0 else { return nil }
        let start = strokes[index]
        let end = index + 1 < strokes.count ? strokes[index + 1] : start
        return ReplayStrokePose.computeAtTime(
            frame: frame,
            strokeStartTime: start.t,
            strokeEndTime: end.t,
            strokeStartDistance: start.d,
            strokeEndDistance: end.d,
            strokeIndex: index,
            context: context,
            medianHR: medianHR,
            duration: duration
        )
    }

    private func rebuildPoseContexts() {
        (livePoseContext, liveMedianHR) = Self.aggregates(for: detail.strokes, sport: sport)
        if let rival, rival.hasGenuineStrokeData {
            (rivalPoseContext, rivalMedianHR) = Self.aggregates(
                for: rival.strokes,
                sport: sport
            )
        } else {
            rivalPoseContext = nil
            rivalMedianHR = 0
        }
    }

    private static func aggregates(
        for strokes: [Stroke],
        sport: Sport
    ) -> (ReplayStrokePoseContext?, Int) {
        guard !strokes.isEmpty else { return (nil, 0) }
        let watts = strokes.map(\.watts)
        let distances = strokes.indices.dropFirst().compactMap { index -> Double? in
            let value = strokes[index].d - strokes[index - 1].d
            return value.isFinite && value > 0 ? value : nil
        }
        let defaultDistance: Double = switch sport {
        case .rower: 11
        case .skierg: 8
        case .bike: 5
        }
        let context = ReplayStrokePoseContext(
            sport: sport,
            peakWatts: watts.max() ?? 0,
            medianWatts: Int(median(watts.map(Double.init), fallback: 0).rounded()),
            medianDPS: median(distances, fallback: defaultDistance),
            maxHR: strokes.compactMap(\.heartRate).max() ?? 0
        )
        let medianHR = Int(median(strokes.compactMap(\.heartRate).map(Double.init), fallback: 0).rounded())
        return (context, medianHR)
    }

    private static func median(_ values: [Double], fallback: Double) -> Double {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return fallback }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2
            : sorted[middle]
    }

    private func stablePhase(distance: Double) -> Double {
        let safeDistance = distance.isFinite ? max(0, distance) : 0
        return safeDistance / ReplayMotion.metersPerCycle(for: sport) * .pi * 2
    }

    private var canvasAccessibilityValue: String {
        let frame = state.currentFrame
        let ghostDistance = rival.map {
            ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: $0.strokes)
        }
        return Self.canvasAccessibilityValue(
            sport: sport,
            frame: frame,
            distanceUnit: distanceUnit,
            reduceMotion: reduceMotion,
            ghostDistance: ghostDistance
        )
    }

    static func canvasAccessibilityLabel(for sport: Sport) -> String {
        "\(sport.displayName) workout replay"
    }

    static func canvasAccessibilityValue(
        sport: Sport,
        frame: ReplayFrame,
        distanceUnit: DistanceUnit,
        reduceMotion: Bool,
        ghostDistance: Double?
    ) -> String {
        var parts = [
            "Time \(RowPlayFormatting.time(frame.t, tenths: true))",
            "Distance \(RowPlayFormatting.distance(frame.d, unit: distanceUnit))",
            reduceMotion ? "Reduced motion" : "Animated \(sport.displayName) athlete",
        ]
        if let ghostDistance {
            let gap = ReplayRaceGap.raceGapMeters(playerDistance: frame.d, ghostDistance: ghostDistance)
            parts.append(ReplayRivalGapFormatting.metersLabel(gap, unit: distanceUnit))
        }
        return parts.joined(separator: ", ")
    }

    /// Retained as a pure compatibility helper for replay-rival path tests and
    /// export tooling. The production Canvas now renders athletes and venues.
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
}
