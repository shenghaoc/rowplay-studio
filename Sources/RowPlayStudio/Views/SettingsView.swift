import Foundation
import RowPlayCore
import RowPlayPlatform
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @EnvironmentObject private var library: WorkoutLibrary
    @EnvironmentObject private var syncController: Concept2SyncController
    @State private var concept2Token = ""
    @State private var isConfirmingDisconnect = false

    private var isTokenEmpty: Bool {
        concept2Token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var cannotDisconnect: Bool {
        !syncController.isConnected || syncController.isLoading
    }

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
                    Text("Simulated")
                        .foregroundStyle(.secondary)
                }
                Text("Direct Bluetooth connection to Concept2 ergs is coming soon.")
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

                Text("Create a token at log.concept2.com → Edit Profile → Applications.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        syncController.saveToken(concept2Token)
                        concept2Token = ""
                    } label: {
                        Label("Save Token", systemImage: "key")
                    }
                    .disabled(isTokenEmpty)
                    .help(isTokenEmpty
                          ? "Enter a token to save"
                          : "Save your Concept2 API access token to the keychain")

                    Button {
                        Task {
                            await syncController.syncNow(into: library)
                        }
                    } label: {
                        Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .disabled(!syncController.canSync)
                    .help(!syncController.canSync
                          ? "Cannot sync right now"
                          : "Sync workouts from your Concept2 Logbook")

                    Spacer()

                    Button(role: .destructive) {
                        isConfirmingDisconnect = true
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                    .disabled(cannotDisconnect)
                    .help(cannotDisconnect
                          ? "Cannot disconnect right now"
                          : "Disconnect your Concept2 account and delete local data")
                }

                if syncController.syncState.inProgress {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Syncing with Concept2…")
                            .foregroundStyle(.secondary)
                    }
                } else if syncController.isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading workout library…")
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
        .frame(minWidth: 400, idealWidth: 540, maxWidth: 640)
        .confirmationDialog(
            "Disconnect Concept2?",
            isPresented: $isConfirmingDisconnect
        ) {
            Button("Disconnect", role: .destructive) {
                Task {
                    await syncController.disconnect(library: library)
                }
            }
            Button("Keep Connected", role: .cancel) {}
        } message: {
            Text("This removes your saved Concept2 token, clears cached workouts, and deletes all local annotations.")
        }
    }
}
