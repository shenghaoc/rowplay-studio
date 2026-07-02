import SwiftUI

struct SettingsView: View {
    @AppStorage("demoModeEnabled") private var demoModeEnabled = true
    @AppStorage("reduceReplayMotion") private var reduceReplayMotion = false
    @AppStorage("preferredDistanceUnit") private var preferredDistanceUnit = "metric"

    var body: some View {
        Form {
            Section("Library") {
                Toggle("Demo mode", isOn: $demoModeEnabled)
            }

            Section("Replay") {
                Toggle("Reduce motion", isOn: $reduceReplayMotion)
            }

            Section("Units") {
                Picker("Distance", selection: $preferredDistanceUnit) {
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

