import RowPlayCore
import RowPlayPlatform
import SwiftUI

@main
struct RowPlayStudioApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    #endif
    @StateObject private var preferences = AppPreferences()
    private let launchConfiguration: AppLaunchConfiguration
    @StateObject private var library: WorkoutLibrary
    @StateObject private var syncController = Concept2SyncController()

    init() {
        let configuration = AppLaunchConfiguration.fromEnvironment()
        launchConfiguration = configuration
        _library = StateObject(
            wrappedValue: configuration.automationMode
                ? WorkoutLibrary.automationDemo()
                : WorkoutLibrary(
                    details: [],
                    annotationStore: AnnotationStoreFactory.makeDefault()
                )
        )
    }

    var body: some Scene {
        WindowGroup("RowPlay Studio", id: "main") {
            ContentView(library: library)
                #if os(macOS)
                .frame(minWidth: 1_000, minHeight: 680)
                #endif
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
        #if os(macOS)
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
                .help(!syncController.canSync ? "Connect a logbook to sync" : "Sync Concept2 Logbook")
                .accessibilityHint(!syncController.canSync ? "Requires logbook connection" : "Syncs logbook with Concept2")

                Button("Reload Workout Library") {
                    Task {
                        await syncController.loadCachedWorkouts(into: library)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(syncController.isLoading)
                .help(syncController.isLoading ? "Currently loading workouts" : "Reload Workout Library")
                .accessibilityHint(syncController.isLoading ? "Currently loading workouts" : "Reloads the workout library")
            }
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView()
                .environmentObject(preferences)
                .environmentObject(library)
                .environmentObject(syncController)
        }
        #endif
    }
}

#if os(macOS)
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AutomationReadinessTelemetry.recordApplicationLaunch()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}
#endif
