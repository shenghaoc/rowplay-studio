import Foundation
import RowPlayCore
import SwiftUI

struct ReplayView: View {
    let detail: WorkoutDetail
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var state: ReplayState
    @State private var frameVersion = 0
    @State private var playbackTimer: Timer?
    @State private var lastTickDate: Date?

    init(detail: WorkoutDetail) {
        self.detail = detail
        _state = StateObject(wrappedValue: ReplayState(strokes: detail.strokes))
    }

    var body: some View {
        VStack(spacing: 0) {
            replayCanvas
                .frame(minHeight: 300)
            Divider()
            telemetryBar
            Divider()
            playbackControls
        }
        .navigationTitle("Replay")
        .onAppear {
            startTimer()
        }
        .onDisappear {
            state.pause()
            stopTimer()
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

        let maxT = strokes.last?.t ?? 1
        let maxD = strokes.last?.d ?? 1
        guard maxT > 0, maxD > 0 else { return }

        var path = Path()
        for (i, stroke) in strokes.enumerated() {
            let x = CGFloat(stroke.t / maxT) * size.width
            let y = size.height - CGFloat(stroke.d / maxD) * size.height
            if i == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        context.stroke(path, with: .color(machineColor.opacity(0.7)), lineWidth: 2)
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        let maxT = detail.strokes.last?.t ?? 1
        let maxD = detail.strokes.last?.d ?? 1
        guard maxT > 0, maxD > 0 else { return }
        let frame = state.currentFrame

        let x = CGFloat(frame.t / maxT) * size.width
        let y = size.height - CGFloat(frame.d / maxD) * size.height

        // Vertical playhead line
        var playhead = Path()
        playhead.move(to: CGPoint(x: x, y: 0))
        playhead.addLine(to: CGPoint(x: x, y: size.height))
        context.stroke(playhead, with: .color(.red), lineWidth: 1)

        // Current position dot
        let dotSize: CGFloat = 8
        let dot = Path(ellipseIn: CGRect(
            x: x - dotSize / 2,
            y: y - dotSize / 2,
            width: dotSize,
            height: dotSize
        ))
        context.fill(dot, with: .color(.red))
    }

    // MARK: - Telemetry

    private var telemetryBar: some View {
        HStack(spacing: 16) {
            TelemetryItem(label: "Time", value: RowPlayFormatting.time(state.currentFrame.t, tenths: true))
            TelemetryItem(label: "Distance", value: RowPlayFormatting.distance(state.currentFrame.d))
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
            // Play/Pause
            Button(action: {
                state.toggle()
                markFrameChanged()
            }) {
                Image(systemName: state.playing ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .keyboardShortcut(.space, modifiers: [])

            // Scrubber
            Slider(
                value: Binding(
                    get: { state.time },
                    set: {
                        state.seek(to: $0)
                        markFrameChanged()
                    }
                ),
                in: 0...max(state.duration, 1)
            )

            // Speed picker
            Picker("Speed", selection: Binding(
                get: { state.speed },
                set: {
                    state.setSpeed($0)
                    markFrameChanged()
                }
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

    // MARK: - Timer

    private func startTimer() {
        guard playbackTimer == nil else { return }
        lastTickDate = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { _ in
            let now = Date()
            let delta = lastTickDate.map {
                ReplayMotion.clampDt(ms: now.timeIntervalSince($0) * 1_000)
            } ?? 0
            lastTickDate = now

            if state.tick(deltaTime: delta) {
                markFrameChanged()
            }
        }
        timer.tolerance = 1.0 / 120.0
        RunLoop.main.add(timer, forMode: .common)
        playbackTimer = timer
    }

    private func stopTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
        lastTickDate = nil
        markFrameChanged()
    }

    private func markFrameChanged() {
        frameVersion &+= 1
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
    }
}

// Placeholder for a proper display link integration.
private struct DisplayLinkPublisher {
    // Future: wrap CVDisplayLink or CADisplayLink for precise timing.
}

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
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
