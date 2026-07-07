import Foundation
import RowPlayCore
import SwiftUI

struct ReplayView: View {
    let detail: WorkoutDetail
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var preferences: AppPreferences
    @State private var state: ReplayState
    @State private var lastTickDate: Date?

    private var unit: DistanceUnit { preferences.distanceUnit }
    private var reduceMotion: Bool { preferences.reduceReplayMotion }

    init(detail: WorkoutDetail) {
        self.detail = detail
        _state = State(initialValue: ReplayState(strokes: detail.strokes))
    }

    var body: some View {
        // Reduce Motion lowers the replay tick rate while keeping playback controls functional.
        let interval = reduceMotion ? 1.0 / 15.0 : 1.0 / 60.0
        TimelineView(.animation(minimumInterval: interval, paused: !state.playing)) { timelineContext in
            VStack(spacing: 0) {
                replayCanvas
                    .frame(minHeight: 300)
                Divider()
                telemetryBar
                Divider()
                playbackControls
            }
            .onChange(of: timelineContext.date) { oldDate, newDate in
                guard state.playing else {
                    lastTickDate = newDate
                    return
                }
                let delta = lastTickDate.map {
                    ReplayMotion.clampDt(ms: newDate.timeIntervalSince($0) * 1_000)
                } ?? 0
                lastTickDate = newDate
                state.tick(deltaTime: delta)
            }
        }
        .navigationTitle("Replay")
        .onDisappear {
            state.pause()
        }
    }

    // MARK: - Canvas

    private var replayCanvas: some View {
        Canvas { context, size in
            drawStrokePath(in: &context, size: size)
            drawPlayhead(in: &context, size: size)
        }
    }

    private func drawStrokePath(in context: inout GraphicsContext, size: CGSize) {
        let strokes = detail.strokes
        guard strokes.count > 1 else { return }

        let originT = strokes[0].t
        let maxT = strokes.last?.t ?? originT
        let duration = maxT - originT
        let maxD = strokes.last?.d ?? 1
        guard duration.isFinite, duration > 0, maxD.isFinite, maxD > 0 else { return }

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

        context.stroke(path, with: .color(machineColor.opacity(0.7)), lineWidth: 2)
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
        context.stroke(playhead, with: .color(.red), lineWidth: 1)

        let dotSize: CGFloat = 8
        let dot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2,
            y: y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        context.fill(dot, with: .color(.red))
    }

    private func unitFraction(_ numerator: Double, denominator: Double) -> CGFloat {
        guard numerator.isFinite, denominator.isFinite, denominator > 0 else { return 0 }
        return CGFloat(max(0, min(1, numerator / denominator)))
    }

    // MARK: - Telemetry

    private var telemetryBar: some View {
        HStack(spacing: 16) {
            TelemetryItem(label: "Time", value: RowPlayFormatting.time(state.currentFrame.t, tenths: true))
            TelemetryItem(label: "Distance", value: RowPlayFormatting.distance(state.currentFrame.d, unit: unit))
            TelemetryItem(label: "Pace", value: RowPlayFormatting.pace(state.currentFrame.pace))
            TelemetryItem(label: detail.workout.sport.cadenceUnit, value: cadenceText)
            TelemetryItem(label: "Watts", value: "\(state.currentFrame.watts)")
            if let hr = state.currentFrame.heartRate {
                TelemetryItem(label: "HR", value: "\(hr)")
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal)
        .background(.ultraThinMaterial)
    }

    private var cadenceText: String {
        guard state.currentFrame.cadence.isFinite else { return "-" }
        return String(Int(state.currentFrame.cadence.rounded()))
    }

    private var machineColor: Color {
        let color = ReplaySportThemeLookup.machineColor(for: detail.workout.sport)
        return Color(hex: colorScheme == .dark ? color.dark : color.light)
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            Button(action: { state.toggle() }) {
                Image(systemName: state.playing ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
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

// MARK: - Telemetry Item

private struct TelemetryItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.medium))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
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
