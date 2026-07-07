import Foundation
import RowPlayCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: WorkoutLibrary
    @EnvironmentObject private var syncController: Concept2SyncController
    @State private var concept2Token = ""
    @State private var isConfirmingDisconnect = false

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

            Section("Concept2") {
                HStack(alignment: .firstTextBaseline) {
                    Label("Logbook", systemImage: syncController.isConnected ? "checkmark.circle" : "person.crop.circle.badge.plus")
                    Spacer()
                    Text(syncController.isConnected ? "Connected" : "Not connected")
                        .foregroundStyle(.secondary)
                }

                SecureField("Access token", text: $concept2Token)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button {
                        syncController.saveToken(concept2Token)
                        concept2Token = ""
                    } label: {
                        Label("Save Token", systemImage: "key")
                    }
                    .disabled(concept2Token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        Task {
                            await syncController.syncNow(into: library)
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!syncController.canSync)

                    Spacer()

                    Button(role: .destructive) {
                        isConfirmingDisconnect = true
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(!syncController.isConnected || syncController.syncState.inProgress)
                }

                if syncController.syncState.inProgress {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing")
                            .foregroundStyle(.secondary)
                    }
                } else if let statusMessage = syncController.statusMessage {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Units") {
                Picker("Distance", selection: $preferences.distanceUnit) {
                    Text("Metric").tag(DistanceUnit.metric)
                    Text("Imperial").tag(DistanceUnit.imperial)
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420)
        .confirmationDialog(
            "Disconnect Concept2?",
            isPresented: $isConfirmingDisconnect
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await syncController.disconnect(library: library)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes the saved token and clears cached Concept2 workouts from this Mac.")
        }
    }
}
