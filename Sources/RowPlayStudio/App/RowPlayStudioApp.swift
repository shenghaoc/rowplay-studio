import AppKit
import RowPlayCore
import RowPlayPlatform
import SwiftUI

@main
struct RowPlayStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences = AppPreferences()
    private let launchConfiguration: AppLaunchConfiguration
    @StateObject private var library: WorkoutLibrary
    @StateObject private var syncController = Concept2SyncController()

    init() {
        let configuration = AppLaunchConfiguration.fromEnvironment()
        launchConfiguration = configuration
        _library = StateObject(
            wrappedValue: configuration.automationMode
                ? WorkoutLibrary.demo()
                : WorkoutLibrary(
                    details: [],
                    annotationStore: AnnotationStoreFactory.makeDefault()
                )
        )
    }

    var body: some Scene {
        WindowGroup("RowPlay Studio", id: "main") {
            ContentView(library: library)
                .frame(minWidth: 1_000, minHeight: 680)
                .environmentObject(preferences)
                .environmentObject(syncController)
                .environment(\.automationModeEnabled, launchConfiguration.automationMode)
                .task {
                    AutomationReadinessTelemetry.recordContentPresented(
                        automationMode: launchConfiguration.automationMode
                    )
                    if !launchConfiguration.automationMode {
                        await syncController.loadCachedWorkouts(into: library)
                    }
                }
        }
        .commands {
            SidebarCommands()
            CommandMenu("Workout") {
                Button("Sync Concept2 Logbook") {
                    Task {
                        await syncController.syncNow(into: library)
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!syncController.canSync)

                Button("Reload Workout Library") {
                    Task {
                        await syncController.loadCachedWorkouts(into: library)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(syncController.syncState.inProgress)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(library)
                .environmentObject(syncController)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AutomationReadinessTelemetry.recordApplicationLaunch()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
