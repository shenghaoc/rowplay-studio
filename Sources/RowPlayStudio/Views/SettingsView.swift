import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        Form {
            Section("Library") {
                Toggle("Demo mode", isOn: $preferences.demoModeEnabled)
            }

            Section("Replay") {
                Toggle("Reduce motion", isOn: $preferences.reduceReplayMotion)
            }

            Section("Hardware") {
                HStack(alignment: .firstTextBaseline) {
                    Label("Erg connection", systemImage: "dot.radiowaves.left.and.right")
                    Spacer()
                    Text("Mock only")
                        .foregroundStyle(.secondary)
                }
                Text("Bluetooth devices are not available in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Units") {
                Picker("Distance", selection: $preferences.preferredDistanceUnit) {
                    Text("Metric").tag("metric")
                    Text("Imperial").tag("imperial")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
    }
}
