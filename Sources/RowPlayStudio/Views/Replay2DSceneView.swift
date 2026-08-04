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
///
/// The production renderer deliberately remains an immediate-mode `Canvas`:
/// its fixed authored geometry mirrors the pinned web renderer, redraw cost is
/// bounded by a small deterministic path set, and no retained scene graph can
/// accumulate stale contact state while scrubbing or switching rivals.
struct Replay2DSceneView: View {
    let detail: WorkoutDetail
    @Binding var state: ReplayState
    let rival: ReplayRival?
    let distanceUnit: DistanceUnit
    let reduceMotion: Bool
    let contentRevision: UInt64

    @Environment(\.colorScheme) private var colorScheme
    @State private var lastTickDate: Date?
    @State private var livePoseAggregates: ReplayStrokePoseAggregates?
    @State private var rivalPoseAggregates: ReplayStrokePoseAggregates?

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
                liveDistance: frame.d,
                ghostDistance: ghost.pose == nil ? nil : ghost.distance,
                progress: frame.progress
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
        let labelContext = context
        let labelCenterY = max(14, top - 9)
        let labelWidth = isRival ? 48.0 : 38.0
        labelContext.fill(
            Replay2DFigure.roundedRectPath(
                x - labelWidth / 2,
                labelCenterY - 8,
                labelWidth,
                16,
                6
            ),
            with: .color(Replay2DStyle.hudBackdrop)
        )
        labelContext.draw(
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isRival ? Replay2DStyle.hudRivalText : Replay2DStyle.hudText),
            at: CGPoint(x: x, y: labelCenterY),
            anchor: .center
        )
    }

    private func drawSecondaryHUD(
        _ context: GraphicsContext,
        size: CGSize,
        liveDistance: Double,
        ghostDistance: Double?,
        progress: Double
    ) {
        let layout = Replay2DHUDRenderer.layout(size: size, progress: progress)
        context.fill(
            Replay2DFigure.roundedRectPath(
                layout.backdrop.minX,
                layout.backdrop.minY,
                layout.backdrop.width,
                layout.backdrop.height,
                8
            ),
            with: .color(Replay2DStyle.hudBackdrop)
        )

        context.draw(
            Text(Replay2DHUDRenderer.progressLabel(progress))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(Replay2DStyle.hudText),
            at: CGPoint(x: size.width / 2, y: layout.summaryY),
            anchor: .center
        )

        let cueFont = Font.system(size: 10, weight: .bold, design: .monospaced)
        context.draw(
            Text("START").font(cueFont).foregroundStyle(Replay2DStyle.hudText),
            at: CGPoint(x: layout.backdrop.minX + 8, y: layout.trackY),
            anchor: .leading
        )
        context.draw(
            Text("FINISH").font(cueFont).foregroundStyle(Replay2DStyle.hudText),
            at: CGPoint(x: layout.backdrop.maxX - 8, y: layout.trackY),
            anchor: .trailing
        )
        context.stroke(
            Replay2DFigure.linePath(
                layout.trackStartX,
                layout.trackY,
                layout.trackEndX,
                layout.trackY
            ),
            with: .color(Replay2DStyle.hudTrack),
            style: StrokeStyle(lineWidth: 4, lineCap: .round)
        )
        if layout.markerX > layout.trackStartX {
            context.stroke(
                Replay2DFigure.linePath(
                    layout.trackStartX,
                    layout.trackY,
                    layout.markerX,
                    layout.trackY
                ),
                with: .color(Replay2DStyle.hudProgress),
                style: StrokeStyle(lineWidth: 4, lineCap: .round)
            )
        }
        Replay2DFigure.disc(
            context,
            layout.markerX,
            layout.trackY,
            3.5,
            color: Replay2DStyle.hudProgress
        )

        let left = Text(RowPlayFormatting.time(state.time, tenths: true))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Replay2DStyle.hudText)
        let right = Text(RowPlayFormatting.distance(liveDistance, unit: distanceUnit))
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Replay2DStyle.hudText)
        context.draw(
            left,
            at: CGPoint(x: layout.backdrop.minX + 8, y: layout.metricsY),
            anchor: .leading
        )
        context.draw(
            right,
            at: CGPoint(x: layout.backdrop.maxX - 8, y: layout.metricsY),
            anchor: .trailing
        )
        if let ghostDistance {
            let gap = ReplayRaceGap.raceGapMeters(
                playerDistance: liveDistance,
                ghostDistance: ghostDistance
            )
            context.draw(
                Text(ReplayRivalGapFormatting.metersLabel(gap, unit: distanceUnit))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Replay2DStyle.hudRivalText),
                at: CGPoint(x: size.width / 2, y: layout.metricsY),
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
        guard case let .genuine(aggregates) = Replay2DStrokeArticulation.select(
            cachedAggregates: livePoseAggregates,
            hasUsableStrokeData: !detail.strokes.isEmpty
        ) else { return fallback }
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
            context: aggregates.context,
            medianHR: aggregates.medianHeartRate,
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
        guard case let .genuine(aggregates) = Replay2DStrokeArticulation.select(
            cachedAggregates: rivalPoseAggregates,
            hasUsableStrokeData: rival.hasGenuineStrokeData
        ) else {
            return (fallback, frame.d)
        }
        let origin = rival.strokes.first?.t ?? 0
        let duration = max(1, (rival.strokes.last?.t ?? origin) - origin)
        return (
            pose(
                at: absoluteTime,
                frame: frame,
                strokes: rival.strokes,
                context: aggregates.context,
                medianHR: aggregates.medianHeartRate,
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
        livePoseAggregates = ReplayStrokePoseAggregates(
            strokes: detail.strokes,
            sport: sport
        )
        if let rival, rival.hasGenuineStrokeData {
            rivalPoseAggregates = ReplayStrokePoseAggregates(
                strokes: rival.strokes,
                sport: sport
            )
        } else {
            rivalPoseAggregates = nil
        }
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
            rival: rival,
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
        rival: ReplayRival?,
        ghostDistance: Double?
    ) -> String {
        let progress = ReplayTelemetryFormatting.roundedInteger(
            Replay2DHUDRenderer.clampedProgress(frame.progress) * 100,
            fallback: "0"
        )
        var parts = [
            "Time \(RowPlayFormatting.time(frame.t, tenths: true))",
            "Progress \(progress)%",
            "Pace \(RowPlayFormatting.pace(frame.pace))",
            "Distance \(RowPlayFormatting.distance(frame.d, unit: distanceUnit))",
            reduceMotion ? "Reduced motion" : "Animated \(sport.displayName) athlete",
        ]
        if let rival {
            parts.append("Rival \(rivalAccessibilityIdentity(rival))")
            if let ghostDistance {
                let gap = ReplayRaceGap.raceGapMeters(
                    playerDistance: frame.d,
                    ghostDistance: ghostDistance
                )
                parts.append("Gap \(ReplayRivalGapFormatting.metersLabel(gap, unit: distanceUnit))")
            } else {
                parts.append("Gap unavailable")
            }
        } else {
            parts.append("No rival")
        }
        return parts.joined(separator: ", ")
    }

    static func rivalAccessibilityIdentity(_ rival: ReplayRival) -> String {
        switch rival.kind {
        case .session:
            "session \(rival.displayLabel)"
        case .constantPace:
            "pace boat \(rival.displayLabel)"
        case .importedFile:
            "imported file \(rival.localFileName ?? rival.displayLabel)"
        }
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

struct Replay2DHUDLayout: Equatable {
    let backdrop: CGRect
    let summaryY: Double
    let trackY: Double
    let metricsY: Double
    let trackStartX: Double
    let trackEndX: Double
    let markerX: Double
}

/// Pure layout and formatting boundary for the Canvas progress HUD. Exact
/// marker geometry makes start, midpoint, finish, and seek states testable
/// independently of font rasterization.
enum Replay2DHUDRenderer {
    static func clampedProgress(_ progress: Double) -> Double {
        Replay2DStyle.clamp01(progress)
    }

    static func progressLabel(_ progress: Double) -> String {
        let percent = ReplayTelemetryFormatting.roundedInteger(
            clampedProgress(progress) * 100,
            fallback: "0"
        )
        return "\(percent)% complete"
    }

    static func layout(size: CGSize, progress: Double) -> Replay2DHUDLayout {
        let width = max(0, Double(size.width))
        let height = max(0, Double(size.height))
        let backdrop = CGRect(
            x: 12,
            y: max(0, height - 58),
            width: max(0, width - 24),
            height: min(52, height)
        )
        let trackStartX = min(backdrop.maxX, backdrop.minX + 68)
        let trackEndX = max(trackStartX, backdrop.maxX - 72)
        let markerX = trackStartX
            + (trackEndX - trackStartX) * clampedProgress(progress)
        return Replay2DHUDLayout(
            backdrop: backdrop,
            summaryY: max(0, height - 48),
            trackY: max(0, height - 33),
            metricsY: max(0, height - 15),
            trackStartX: trackStartX,
            trackEndX: trackEndX,
            markerX: markerX
        )
    }
}

/// Pure cache gate used by both live and rival 2D articulation. A missing
/// precomputed value always selects the deterministic fallback; frame-time code
/// never rebuilds medians to cover an appearance-order race.
enum Replay2DStrokeArticulation: Equatable {
    case genuine(ReplayStrokePoseAggregates)
    case fallback

    static func select(
        cachedAggregates: ReplayStrokePoseAggregates?,
        hasUsableStrokeData: Bool
    ) -> Replay2DStrokeArticulation {
        guard hasUsableStrokeData, let cachedAggregates else { return .fallback }
        return .genuine(cachedAggregates)
    }
}
