import Foundation
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct ReplayView: View {
    static let qualityAccessibilityLabel = "3D replay quality"
    static let qualityPickerHelp = "Choose the maximum 3D replay quality"
    static let adaptiveQualityHelp = "Quality was reduced to maintain replay performance"

    let detail: WorkoutDetail
    let ghostCandidates: [WorkoutDetail]
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.automationModeEnabled) private var automationModeEnabled
    @State private var state: ReplayState
    @State private var lastTickDate: Date?
    @State private var rendererMode: ReplayRendererMode = .threeD
    @State private var cameraPreset: ReplayCameraPreset = .chase
    @State private var effectiveReplayQuality: ReplayRenderQuality?
    @State private var cameraResetGeneration = 0
    @State private var replayDiscontinuityGeneration = 0
    @State private var strokePath = Path()
    @State private var ghostStrokePath = Path()
    @State private var canvasSize: CGSize = .zero
    @State private var cachedMachineColor: Color = .accentColor
    @State private var selectedGhostID: Int?

    private var unit: DistanceUnit { preferences.distanceUnit }
    private var reduceMotion: Bool { preferences.reduceReplayMotion || automationModeEnabled }

    /// The active ghost detail resolved from the fixed candidate snapshot.
    private var activeGhostDetail: WorkoutDetail? {
        guard let selectedGhostID else { return nil }
        return ghostCandidates.first { $0.id == selectedGhostID }
    }

    init(
        detail: WorkoutDetail,
        ghostCandidates: [WorkoutDetail] = [],
        initialGhostID: Int? = nil
    ) {
        self.detail = detail
        self.ghostCandidates = ghostCandidates
        _state = State(initialValue: ReplayState(strokes: detail.strokes))
        let validID = initialGhostID.flatMap { id in
            ghostCandidates.contains(where: { $0.id == id }) ? id : nil
        }
        _selectedGhostID = State(initialValue: validID)
    }

    var body: some View {
        VStack(spacing: 0) {
            rendererPicker
            rivalControlBand
            replaySurface
            Divider()
            telemetryBar
            Divider()
            playbackControls
        }
        .navigationTitle("Replay")
        .onChange(of: state.playing) { _, playing in
            if playing {
                lastTickDate = nil
            }
        }
        .onDisappear {
            state.pause()
        }
        .onChange(of: preferences.replayRenderQuality) { _, quality in
            effectiveReplayQuality = quality
        }
        .onChange(of: selectedGhostID) { _, _ in
            replayDiscontinuityGeneration &+= 1
            ghostStrokePath = Path()
            if canvasSize != .zero {
                if let ghost = activeGhostDetail {
                    ghostStrokePath = makeGhostStrokePath(
                        ghostStrokes: ghost.strokes,
                        playerStrokes: detail.strokes,
                        size: canvasSize
                    )
                }
            }
        }
    }

    // MARK: - Renderer Picker

    private var rendererPicker: some View {
        HStack(spacing: AppDesign.Spacing.medium) {
            Spacer()
            Picker("Renderer", selection: Binding(
                get: { rendererMode },
                set: { mode in
                    lastTickDate = nil
                    rendererMode = mode
                }
            )) {
                ForEach(visibleRendererModes) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)

            if Self.showsQualityControl(rendererMode: rendererMode) {
                Divider()
                    .frame(height: 20)

                Picker(selection: $cameraPreset) {
                    ForEach(ReplayCameraPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                } label: {
                    Label(cameraPreset.displayName, systemImage: cameraPreset.systemImage)
                }
                .pickerStyle(.menu)
                .labelStyle(.iconOnly)
                .accessibilityLabel("Replay camera")
                .accessibilityValue(cameraPreset.displayName)
                #if os(macOS)
                .help("Replay camera")
                #endif

                qualityPicker

                Button {
                    cameraResetGeneration &+= 1
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Reset replay camera")
                #if os(macOS)
                .help("Reset replay camera")
                #endif
            }
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    // MARK: - Rival Control Band

    private var rivalControlBand: some View {
        HStack(spacing: AppDesign.Spacing.medium) {
            Menu {
                Button {
                    selectedGhostID = nil
                } label: {
                    HStack {
                        Text("No Rival")
                        if selectedGhostID == nil {
                            Image(systemName: "checkmark")
                        }
                    }
                }

                if !ghostCandidates.isEmpty {
                    Button {
                        selectedGhostID = ghostCandidates.first?.id
                    } label: {
                        HStack {
                            Text("Best Match")
                            if selectedGhostID == ghostCandidates.first?.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }

                if !ghostCandidates.isEmpty {
                    Divider()

                    ForEach(ghostCandidates) { candidate in
                        Button {
                            selectedGhostID = candidate.id
                        } label: {
                            HStack {
                                Text(candidateLabel(for: candidate))
                                if selectedGhostID == candidate.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                Label("Replay rival", systemImage: "person.2.fill")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Replay rival")
            .accessibilityValue(rivalAccessibilityValue)
            #if os(macOS)
            .help(ghostCandidates.isEmpty
                  ? "No comparable workout with stroke data"
                  : "Choose a past session to race against")
            #endif
            .disabled(ghostCandidates.isEmpty)

            if let active = activeGhostDetail {
                rivalGapDisplay(for: active)
            }

            Spacer()

            if activeGhostDetail != nil {
                Button {
                    selectedGhostID = nil
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove replay rival")
                #if os(macOS)
                .help("Remove replay rival")
                #endif
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    private func candidateLabel(for candidate: WorkoutDetail) -> String {
        let w = candidate.workout
        let dateStr = w.date.formatted(date: .abbreviated, time: .omitted)
        let distStr = RowPlayFormatting.distance(w.distance, unit: unit)
        let paceStr = RowPlayFormatting.pace(w.pace)
        return "\(dateStr) · \(distStr) · \(paceStr)"
    }

    private var rivalAccessibilityValue: String {
        if ghostCandidates.isEmpty {
            return "No comparable workout available"
        }
        if let active = activeGhostDetail {
            let w = active.workout
            let dist = RowPlayFormatting.distance(w.distance, unit: unit)
            let pace = RowPlayFormatting.pace(w.pace)
            return "Rival: \(dist) at \(pace) from \(w.date.formatted(date: .abbreviated, time: .omitted))"
        }
        return "No rival selected"
    }

    @ViewBuilder
    private func rivalGapDisplay(for ghost: WorkoutDetail) -> some View {
        let frame = state.currentFrame
        let ghostDist = ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: ghost.strokes)
        let gapM = ReplayRaceGap.raceGapMeters(
            playerDistance: frame.d,
            ghostDistance: ghostDist
        )
        let gapS = ReplayRaceGap.raceGapSeconds(
            gapMeters: gapM,
            playerPacePer500m: frame.pace
        )
        let gapColor = AppDesign.deltaColor(gapM, higherIsBetter: true)

        HStack(spacing: AppDesign.Spacing.small) {
            Text(ghost.workout.date.formatted(date: .abbreviated, time: .omitted))
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)

            Text(gapLabel(meters: gapM))
                .font(AppDesign.Typography.compactLabel.monospacedDigit())
                .foregroundStyle(gapColor)

            Text("·")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(gapSecondsLabel(seconds: gapS))
                .font(AppDesign.Typography.compactLabel.monospacedDigit())
                .foregroundStyle(gapColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Race gap")
        .accessibilityValue("\(gapLabel(meters: gapM)), \(gapSecondsLabel(seconds: gapS))")
    }

    private func gapLabel(meters: Double) -> String {
        let safeM = meters.isFinite ? meters : 0
        if abs(safeM) < 0.5 { return "Level" }
        let prefix = safeM > 0 ? "Ahead" : "Behind"
        let dist = RowPlayFormatting.distance(abs(safeM), unit: unit)
        return "\(prefix) \(dist)"
    }

    private func gapSecondsLabel(seconds: Double) -> String {
        let safeS = seconds.isFinite ? seconds : 0
        let absS = abs(safeS)
        if absS < 0.05 { return "0.0 s" }
        let sign = safeS > 0 ? "+" : "-"
        return "\(sign)\(String(format: "%.1f", absS)) s"
    }

    private var visibleRendererModes: [ReplayRendererMode] {
        ReplayRendererMode.allCases
    }

    // MARK: - Replay Surface

    @ViewBuilder
    private var replaySurface: some View {
        switch rendererMode {
        case .twoD:
            twoDReplaySurface
        case .threeD:
            RealityReplaySceneView(
                detail: detail,
                state: $state,
                reduceMotion: reduceMotion,
                ghostDetail: activeGhostDetail,
                selectedQuality: preferences.replayRenderQuality,
                effectiveQuality: Binding(
                    get: { displayedEffectiveReplayQuality },
                    set: { effectiveReplayQuality = $0 }
                ),
                cameraPreset: cameraPreset,
                cameraResetGeneration: cameraResetGeneration,
                replayDiscontinuityGeneration: replayDiscontinuityGeneration
            )
            .id(Replay3DSceneIdentity(
                workoutID: detail.id,
                ghostWorkoutID: activeGhostDetail?.id,
                sportRawValue: detail.workout.sport.rawValue
            ))
            .frame(minHeight: 300)
        }
    }

    private var qualityPicker: some View {
        HStack(spacing: AppDesign.Spacing.small) {
            Picker(selection: Binding(
                get: { preferences.replayRenderQuality.rawValue },
                set: { rawValue in
                    guard let quality = ReplayRenderQuality(rawValue: rawValue) else { return }
                    effectiveReplayQuality = quality
                    preferences.replayRenderQuality = quality
                }
            )) {
                ForEach(ReplayRenderQuality.allCases, id: \.rawValue) { quality in
                    Text(quality.replayDisplayName).tag(quality.rawValue)
                }
            } label: {
                Label(Self.qualityAccessibilityLabel, systemImage: "slider.horizontal.3")
            }
            .pickerStyle(.menu)
            .labelStyle(.iconOnly)
            .accessibilityLabel(Self.qualityAccessibilityLabel)
            .accessibilityValue(Self.qualityAccessibilityValue(
                selected: preferences.replayRenderQuality,
                effective: displayedEffectiveReplayQuality
            ))
            #if os(macOS)
            .help(Self.qualityPickerHelp)
            #endif

            if Self.isAdaptiveReduction(
                selected: preferences.replayRenderQuality,
                effective: displayedEffectiveReplayQuality
            ) {
                Image(systemName: "arrow.down.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Self.adaptiveQualityAccessibilityLabel(
                        effective: displayedEffectiveReplayQuality
                    ))
                    #if os(macOS)
                    .help(Self.adaptiveQualityHelp)
                    #endif
            }
        }
    }

    static func qualityAccessibilityValue(
        selected: ReplayRenderQuality,
        effective: ReplayRenderQuality
    ) -> String {
        "Selected \(selected.replayDisplayName), effective \(effective.replayDisplayName)"
    }

    static func adaptiveQualityAccessibilityLabel(
        effective: ReplayRenderQuality
    ) -> String {
        "3D replay quality reduced to \(effective.replayDisplayName)"
    }

    static func showsQualityControl(rendererMode: ReplayRendererMode) -> Bool {
        rendererMode == .threeD
    }

    static func isAdaptiveReduction(
        selected: ReplayRenderQuality,
        effective: ReplayRenderQuality
    ) -> Bool {
        // A stale report can briefly sit above a newly synchronized ceiling;
        // only a strictly lower tier represents adaptive degradation.
        effective.maximumDegradationLevel < selected.maximumDegradationLevel
    }

    static func effectiveQualityForDisplay(
        selected: ReplayRenderQuality,
        reportedEffective: ReplayRenderQuality?
    ) -> ReplayRenderQuality {
        reportedEffective ?? selected
    }

    private var displayedEffectiveReplayQuality: ReplayRenderQuality {
        Self.effectiveQualityForDisplay(
            selected: preferences.replayRenderQuality,
            reportedEffective: effectiveReplayQuality
        )
    }

    private var twoDReplaySurface: some View {
        // Reduce Motion lowers the replay tick rate while keeping playback controls functional.
        let interval = reduceMotion ? 1.0 / 15.0 : 1.0 / 60.0
        return TimelineView(.animation(minimumInterval: interval, paused: !state.playing)) { timelineContext in
            replayCanvas
                .onChange(of: timelineContext.date) { oldDate, newDate in
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
    }

    // MARK: - Canvas

    private var replayCanvas: some View {
        Canvas { context, size in
            // Ghost path (behind live path)
            context.stroke(ghostStrokePath, with: .color(AppDesign.softPurple.opacity(0.35)), lineWidth: 1.5)
            // Live path (dominant)
            context.stroke(strokePath, with: .color(cachedMachineColor.opacity(0.7)), lineWidth: 2)
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
                        strokePath = self.makeStrokePath(strokes: detail.strokes, size: newSize)
                        if let ghost = activeGhostDetail {
                            ghostStrokePath = makeGhostStrokePath(
                                ghostStrokes: ghost.strokes,
                                playerStrokes: detail.strokes,
                                size: newSize
                            )
                        }
                    }
            }
        )
        .onAppear {
            cachedMachineColor = Self.machineColor(for: detail.workout.sport, colorScheme: colorScheme)
        }
        .onChange(of: colorScheme) { _, scheme in
            cachedMachineColor = Self.machineColor(for: detail.workout.sport, colorScheme: scheme)
        }
        .onChange(of: detail.id) { _, _ in
            strokePath = self.makeStrokePath(strokes: detail.strokes, size: canvasSize)
            cachedMachineColor = Self.machineColor(for: detail.workout.sport, colorScheme: colorScheme)
            if let selectedGhostID,
               !ghostCandidates.contains(where: { $0.id == selectedGhostID }) {
                self.selectedGhostID = nil
            }
            ghostStrokePath = Path()
            if canvasSize != .zero, let ghost = activeGhostDetail {
                ghostStrokePath = makeGhostStrokePath(
                    ghostStrokes: ghost.strokes,
                    playerStrokes: detail.strokes,
                    size: canvasSize
                )
            }
        }
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        let duration = state.duration
        let maxD = detail.strokes.last?.d ?? 1
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return }
        let frame = state.currentFrame

        let x = unitFraction(frame.t, denominator: duration) * size.width
        let y = size.height - unitFraction(frame.d, denominator: maxD) * size.height

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
        guard let ghost = activeGhostDetail, !ghost.strokes.isEmpty else { return }
        let duration = state.duration
        let maxD = detail.strokes.last?.d ?? 1
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return }

        let ghostDist = ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: ghost.strokes)
        guard ghostDist.isFinite, ghostDist >= 0 else { return }

        let x = unitFraction(state.time, denominator: duration) * size.width
        let y = size.height - unitFraction(ghostDist, denominator: maxD) * size.height

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
        context.stroke(strokeDot, with: .color(cachedMachineColor.opacity(0.3)), lineWidth: 1)
        context.fill(dot, with: .color(ghostColor.opacity(0.8)))
    }

    private func unitFraction(_ numerator: Double, denominator: Double) -> CGFloat {
        guard numerator.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return CGFloat(max(0, min(1, numerator / denominator)))
    }

    /// Precomputes the full stroke trail path so the Canvas draw closure only strokes it.
    func makeStrokePath(strokes: [Stroke], size: CGSize) -> Path {
        guard strokes.count > 1 else { return Path() }

        let originT = strokes[0].t
        let maxT = strokes.last?.t ?? originT
        let maxD = strokes.last?.d ?? 1
        let duration = maxT - originT
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return Path() }

        var path = Path()
        for (i, stroke) in strokes.enumerated() {
            let x = unitFraction(stroke.t - originT, denominator: duration) * size.width
            let y = size.height - unitFraction(stroke.d, denominator: maxD) * size.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }
        return path
    }

    /// Precomputes the ghost stroke trail path using player chart scales
    /// for direct comparability.
    func makeGhostStrokePath(
        ghostStrokes: [Stroke],
        playerStrokes: [Stroke],
        size: CGSize
    ) -> Path {
        guard ghostStrokes.count > 1, playerStrokes.count > 1 else { return Path() }

        let playerOriginT = playerStrokes[0].t
        let ghostOriginT = ghostStrokes[0].t
        let maxT = playerStrokes.last?.t ?? playerOriginT
        let maxD = playerStrokes.last?.d ?? 1
        let duration = maxT - playerOriginT
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return Path() }

        var path = Path()
        var firstPoint = true
        for stroke in ghostStrokes {
            // Sessions have independent absolute timestamp origins. Plot the ghost
            // by its elapsed time, using the player's duration only as the chart scale.
            let x = unitFraction(stroke.t - ghostOriginT, denominator: duration) * size.width
            let y = size.height - unitFraction(stroke.d, denominator: maxD) * size.height
            let clippedX = max(0, min(size.width, x))
            let clippedY = max(0, min(size.height, y))
            if firstPoint {
                path.move(to: CGPoint(x: clippedX, y: clippedY))
                firstPoint = false
            } else {
                path.addLine(to: CGPoint(x: clippedX, y: clippedY))
            }
        }
        return path
    }

    private var canvasAccessibilityValue: String {
        let frame = state.currentFrame
        var parts: [String] = [
            "Time \(RowPlayFormatting.time(frame.t, tenths: true))",
            "Distance \(RowPlayFormatting.distance(frame.d, unit: unit))"
        ]
        if let ghost = activeGhostDetail {
            let ghostDist = ReplayRaceGap.ghostDistance(elapsed: state.time, strokes: ghost.strokes)
            let gapM = ReplayRaceGap.raceGapMeters(playerDistance: frame.d, ghostDistance: ghostDist)
            parts.append(gapLabel(meters: gapM))
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Telemetry

    private var telemetryBar: some View {
        HStack(spacing: AppDesign.Spacing.xLarge) {
            TelemetryItem(label: "Time", value: RowPlayFormatting.time(state.currentFrame.t, tenths: true), color: AppDesign.MetricColor.duration)
            TelemetryItem(label: "Distance", value: RowPlayFormatting.distance(state.currentFrame.d, unit: unit), color: AppDesign.MetricColor.distance)
            TelemetryItem(label: "Pace", value: RowPlayFormatting.pace(state.currentFrame.pace), color: AppDesign.MetricColor.pace)
            TelemetryItem(label: detail.workout.sport.cadenceUnit, value: cadenceText, color: AppDesign.MetricColor.cadence)
            TelemetryItem(label: "Watts", value: "\(state.currentFrame.watts)", color: AppDesign.MetricColor.watts)
            if let hr = state.currentFrame.heartRate {
                TelemetryItem(label: "HR", value: "\(hr)", color: AppDesign.MetricColor.heartRate)
            }
        }
        .padding(.vertical, AppDesign.Spacing.medium)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    private var cadenceText: String {
        guard state.currentFrame.cadence.isFinite else { return "-" }
        return String(Int(state.currentFrame.cadence.rounded()))
    }

    static func machineColor(for sport: Sport, colorScheme: ColorScheme) -> Color {
        let color = ReplaySportThemeLookup.machineColor(for: sport)
        return Color(hex: colorScheme == .dark ? color.dark : color.light)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        let playPauseLabel: LocalizedStringKey = state.playing ? "Pause replay" : "Play replay"

        return HStack(spacing: AppDesign.Spacing.xLarge) {
            PlayPauseButton(isPlaying: state.playing, action: { state.toggle() })
                .accessibilityLabel(playPauseLabel)
                #if os(macOS)
                .help(playPauseLabel)
                #endif
                .keyboardShortcut(.space, modifiers: [])

            Slider(
                value: Binding(
                    get: { state.time },
                    set: { newTime in
                        if newTime != state.time {
                            replayDiscontinuityGeneration &+= 1
                        }
                        state.seek(to: newTime)
                    }
                ),
                in: 0...max(state.duration, 1),
                onEditingChanged: { isEditing in
                    if isEditing { state.pause() }
                }
            )
            .tint(AppDesign.MetricColor.pace)
            .accessibilityLabel("Replay progress")
            .accessibilityValue("\(RowPlayFormatting.time(state.time, tenths: true)) of \(RowPlayFormatting.time(state.duration, tenths: true))")

            Picker("Speed", selection: Binding(
                get: { state.speed },
                set: { state.setSpeed($0) }
            )) {
                ForEach(ReplaySpeed.allCases, id: \.self) { speed in
                    Text(speed.label).tag(speed)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
        }
        .padding()
    }
}

struct Replay3DSceneIdentity: Hashable {
    let workoutID: Int
    let ghostWorkoutID: Int?
    let sportRawValue: String
}

// MARK: - Play/Pause Button

private struct PlayPauseButton: View {
    let isPlaying: Bool
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(.title2)
                .frame(width: 48, height: 48)
                .background(
                    Circle()
                        .fill(isHovering ? Color.accentColor.opacity(0.16) : AppDesign.activeCardBackground)
                )
        }
        .buttonStyle(.plain)
        #if os(macOS)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        #endif
    }
}

/// Shared timeline clock for replay surfaces. Resetting the date on resume
/// makes the first post-pause tick deterministic rather than including the
/// elapsed wall-clock pause duration.
struct ReplayPlaybackTick {
    let rawDelta: TimeInterval?
    let delta: TimeInterval
    let lastTickDate: Date
}

enum ReplayPlaybackClock {
    static func tick(lastTickDate: Date?, currentDate: Date) -> ReplayPlaybackTick {
        guard let lastTickDate else {
            return ReplayPlaybackTick(rawDelta: nil, delta: 0, lastTickDate: currentDate)
        }
        let rawDelta = currentDate.timeIntervalSince(lastTickDate)
        return ReplayPlaybackTick(
            rawDelta: rawDelta,
            delta: ReplayMotion.clampDt(ms: rawDelta * 1_000),
            lastTickDate: currentDate
        )
    }
}

// MARK: - Telemetry Item

private struct TelemetryItem: View {
    let label: String
    let value: String
    var color: Color = .primary

    var body: some View {
        VStack(spacing: AppDesign.Spacing.xxSmall) {
            Text(value)
                .font(AppDesign.Typography.metricValue.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.tertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else {
            self = .accentColor
            return
        }

        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}

extension ReplayRenderQuality {
    var replayDisplayName: String {
        switch self {
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .ultra: "Ultra"
        }
    }
}
