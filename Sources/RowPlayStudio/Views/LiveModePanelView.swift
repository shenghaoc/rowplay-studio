import RowPlayCore
import SwiftUI

struct LiveModePanelView: View {
    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    private let demoTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dot.radiows.left.and.right")
                    .foregroundStyle(library.liveState.status == .polling ? .green : .secondary)
                Text("Live Mode")
                    .font(.headline)
                Spacer()
                if library.liveState.hasWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("\(library.liveState.consecutiveFailures) consecutive failures")
                }
                Toggle("Enable Live Mode", isOn: Binding(
                    get: { library.liveState.enabled },
                    set: { enabled in
                        if enabled {
                            library.startLiveMode()
                        } else {
                            library.stopLiveMode()
                        }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            }

            if library.liveState.enabled {
                sampleSection
                intervalPicker
                statusSection
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .onReceive(demoTimer) { date in
            library.advanceDemoLiveSampleIfDue(at: date)
        }
    }

    // MARK: - Sample Section

    @ViewBuilder
    private var sampleSection: some View {
        if let sample = library.liveSample {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: sample.sport.iconName)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sample.sport.displayName)
                            .font(.subheadline.weight(.medium))
                        Text("Mock workout")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        library.advanceDemoLiveSample()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Refresh demo sample")
                    .help("Refresh demo sample")
                }

                HStack(spacing: 16) {
                    sampleMetric("Distance", RowPlayFormatting.distance(sample.distance, unit: preferences.distanceUnit))
                    sampleMetric("Time", RowPlayFormatting.time(sample.time, tenths: true))
                    sampleMetric("Pace", RowPlayFormatting.pace(sample.pace))
                    sampleMetric("Rate", "\(Int(sample.strokeRate.rounded())) \(sample.sport.cadenceUnit)")
                    if let heartRate = sample.heartRateAvg {
                        sampleMetric("HR", "\(heartRate) bpm")
                    }
                }
            }
        } else {
            Text("Waiting for mock workout")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interval Picker

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Polling Interval")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                ForEach(liveIntervals, id: \.self) { sec in
                    Button(intervalLabel(sec)) {
                        library.setLiveInterval(sec)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(library.liveState.intervalSec == sec ? .accentColor : .secondary)
                }
            }
        }
    }

    // MARK: - Status Section

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()

            if library.liveState.status == .polling {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Polling...")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else {
                HStack {
                    Text("Last poll")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let last = library.liveState.lastPollAt {
                        Text(last, style: .time)
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("—")
                            .font(.caption.monospacedDigit())
                    }
                }
                HStack {
                    Text("Next poll")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let next = library.liveState.nextPollAt {
                        Text(next, style: .timer)
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("—")
                            .font(.caption.monospacedDigit())
                    }
                }
            }

            if library.liveState.status == .error {
                Text("Polling error — retrying with backoff")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Helpers

    private func intervalLabel(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)s" }
        return "\(sec / 60)m"
    }

    private func sampleMetric(_ label: LocalizedStringKey, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit())
        }
        .frame(minWidth: 64, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
