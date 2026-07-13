import Foundation
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct ReplayView: View {
    let detail: WorkoutDetail
    let ghostDetail: WorkoutDetail?
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.automationModeEnabled) private var automationModeEnabled
    @State private var state: ReplayState
    @State private var lastTickDate: Date?
    @State private var rendererMode: ReplayRendererMode = .threeD
    @State private var strokePath = Path()
    @State private var canvasSize: CGSize = .zero
    @State private var cachedMachineColor: Color = .accentColor

    private var unit: DistanceUnit { preferences.distanceUnit }
    private var reduceMotion: Bool { preferences.reduceReplayMotion || automationModeEnabled }

    init(detail: WorkoutDetail, ghostDetail: WorkoutDetail? = nil) {
        self.detail = detail
        self.ghostDetail = ghostDetail
        _state = State(initialValue: ReplayState(strokes: detail.strokes))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode picker
            rendererPicker
            // Replay surface
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
    }

    // MARK: - Renderer Picker

    private var rendererPicker: some View {
        HStack {
            Spacer()
            Picker("Renderer", selection: $rendererMode) {
                ForEach(visibleRendererModes) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 140)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
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
                ghostDetail: ghostDetail
            )
            .frame(minHeight: 300)
        }
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
            context.stroke(strokePath, with: .color(cachedMachineColor.opacity(0.7)), lineWidth: 2)
            drawPlayhead(in: &context, size: size)
        }
        .accessibilityLabel("Workout replay timeline")
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onChange(of: proxy.size, initial: true) { _, newSize in
                        canvasSize = newSize
                        strokePath = self.makeStrokePath(strokes: detail.strokes, size: newSize)
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
                    set: { state.seek(to: $0) }
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
enum ReplayPlaybackClock {
    static func tick(lastTickDate: Date?, currentDate: Date) -> (delta: TimeInterval, lastTickDate: Date) {
        let delta = lastTickDate.map {
            ReplayMotion.clampDt(ms: currentDate.timeIntervalSince($0) * 1_000)
        } ?? 0
        return (delta, currentDate)
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
