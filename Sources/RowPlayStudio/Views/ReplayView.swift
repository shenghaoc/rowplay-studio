import RowPlayCore
import SwiftUI

struct ReplayView: View {
    let detail: WorkoutDetail
    @State private var state: ReplayState
    @State private var timerActive = false

    init(detail: WorkoutDetail) {
        self.detail = detail
        _state = State(initialValue: ReplayState(strokes: detail.strokes))
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
        .onAppear { timerActive = true }
        .onDisappear { timerActive = false }
        .onChange(of: timerActive) { _, active in
            if active { startTimer() }
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

        context.stroke(path, with: .color(.blue.opacity(0.6)), lineWidth: 2)

        // Draw ghost path if we had ghost data (placeholder for future).
        // For now just draw the player path.
    }

    private func drawPlayhead(in context: inout GraphicsContext, size: CGSize) {
        let maxT = detail.strokes.last?.t ?? 1
        let maxD = detail.strokes.last?.d ?? 1
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
        String(Int(state.currentFrame.cadence.rounded()))
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        HStack(spacing: 16) {
            // Play/Pause
            Button(action: { state.toggle() }) {
                Image(systemName: state.playing ? "pause.fill" : "play.fill")
                    .font(.title2)
            }
            .keyboardShortcut(.space, modifiers: [])

            // Scrubber
            Slider(
                value: Binding(
                    get: { state.time },
                    set: { state.seek(to: $0) }
                ),
                in: 0...max(state.duration, 1)
            )

            // Speed picker
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

    // MARK: - Timer

    private func startTimer() {
        // Use a simple Timer-based approach for ticking the replay state.
        // In a future iteration, this could use CADisplayLink for smoother animation.
        // For now, use a 60fps Timer.
        Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            guard timerActive else { return }
            state.tick(deltaTime: 1.0 / 60.0)
        }
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
