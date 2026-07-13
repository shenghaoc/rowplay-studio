import Combine
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct LiveModePanelView: View {
    @ObservedObject var library: WorkoutLibrary
    @EnvironmentObject private var preferences: AppPreferences
    private let demoTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.large) {
            HStack {
                Image(systemName: "dot.radiows.left.and.right")
                    .foregroundStyle(library.liveState.status == .polling ? AppDesign.energeticGreen : .secondary)
                    .accessibilityHidden(true)
                Text("Live Mode")
                    .font(AppDesign.Typography.sectionHeadline)
                Spacer()
                if library.liveState.hasWarning {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppDesign.warmYellow)
                        .help("\(library.liveState.consecutiveFailures) consecutive failures")
                        .accessibilityHint("Shows the count of consecutive live polling failures")
                        .accessibilityLabel("\(library.liveState.consecutiveFailures) consecutive failures")
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
        .padding(AppDesign.Spacing.large)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: AppDesign.Radius.medium))
        .onReceive(demoTimer) { date in
            library.advanceDemoLiveSampleIfDue(at: date)
        }
    }

    // MARK: - Sample Section

    @ViewBuilder
    private var sampleSection: some View {
        if let sample = library.liveSample {
            VStack(alignment: .leading, spacing: AppDesign.Spacing.medium) {
                HStack(spacing: AppDesign.Spacing.medium) {
                    Image(systemName: sample.sport.iconName)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: AppDesign.Spacing.xxSmall) {
                        Text(sample.sport.displayName)
                            .font(AppDesign.Typography.metricValue)
                        Text("Demo sample")
                            .font(AppDesign.Typography.compactLabel)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        library.advanceDemoLiveSample()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh demo sample")
                    .accessibilityHint("Advances to the next simulated live telemetry sample")
                    .accessibilityLabel("Refresh demo sample")
                }

                HStack(spacing: AppDesign.Spacing.xLarge) {
                    sampleMetric("Distance", RowPlayFormatting.distance(sample.distance, unit: preferences.distanceUnit), color: AppDesign.MetricColor.distance)
                    sampleMetric("Time", RowPlayFormatting.time(sample.time, tenths: true), color: AppDesign.MetricColor.duration)
                    sampleMetric("Pace", RowPlayFormatting.pace(sample.pace), color: AppDesign.MetricColor.pace)
                    sampleMetric("Rate", "\(Int(sample.strokeRate.rounded())) \(sample.sport.cadenceUnit)", color: AppDesign.MetricColor.cadence)
                    if let heartRate = sample.heartRateAvg {
                        sampleMetric("HR", "\(heartRate) bpm", color: AppDesign.MetricColor.heartRate)
                    }
                }
            }
        } else {
            Text("Waiting for mock workout")
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Interval Picker

    private var intervalPicker: some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.small) {
            Text("Polling Interval")
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)

            HStack(spacing: AppDesign.Spacing.xSmall) {
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
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xSmall) {
            Divider()

            if library.liveState.status == .polling {
                HStack(spacing: AppDesign.Spacing.small) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("Polling...")
                        .font(AppDesign.Typography.compactLabel)
                        .foregroundStyle(AppDesign.energeticGreen)
                }
            } else {
                HStack {
                    Text("Last poll")
                        .font(AppDesign.Typography.compactLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let last = library.liveState.lastPollAt {
                        Text(last, style: .time)
                            .font(AppDesign.Typography.compactMetric.monospacedDigit())
                    } else {
                        Text("—")
                            .font(AppDesign.Typography.compactMetric.monospacedDigit())
                    }
                }
                HStack {
                    Text("Next poll")
                        .font(AppDesign.Typography.compactLabel)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let next = library.liveState.nextPollAt {
                        Text(next, style: .timer)
                            .font(AppDesign.Typography.compactMetric.monospacedDigit())
                    } else {
                        Text("—")
                            .font(AppDesign.Typography.compactMetric.monospacedDigit())
                    }
                }
            }

            if library.liveState.status == .error {
                Text("Polling error — retrying with backoff")
                    .font(AppDesign.Typography.compactLabel)
                    .foregroundStyle(AppDesign.alertRed)
            }
        }
    }

    // MARK: - Helpers

    private func intervalLabel(_ sec: Int) -> String {
        if sec < 60 { return "\(sec)s" }
        return "\(sec / 60)m"
    }

    private func sampleMetric(_ label: LocalizedStringKey, _ value: String, color: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: AppDesign.Spacing.xxSmall) {
            Text(label)
                .font(AppDesign.Typography.compactLabel)
                .foregroundStyle(.secondary)
            Text(value)
                .font(AppDesign.Typography.compactMetric.monospacedDigit())
                .foregroundStyle(color)
        }
        .frame(minWidth: 64, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}
