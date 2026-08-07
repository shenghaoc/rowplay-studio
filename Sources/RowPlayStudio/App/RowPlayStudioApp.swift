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
            wrappedValue: configuration.usesDeterministicDemoData
                ? WorkoutLibrary.automationDemo()
                : WorkoutLibrary(
                    details: [],
                    annotationStore: AnnotationStoreFactory.makeDefault()
                )
        )
    }

    var body: some Scene {
        WindowGroup("RowPlay Studio", id: "main") {
            rootContent
                #if os(macOS)
                .frame(
                    minWidth: windowMinimumWidth,
                    minHeight: windowMinimumHeight
                )
                #endif
                .environmentObject(preferences)
                .environmentObject(syncController)
                .environment(\.automationModeEnabled, launchConfiguration.automationMode)
                .environment(\.acceptanceModeEnabled, launchConfiguration.acceptanceMode)
                .task {
                    AutomationReadinessTelemetry.recordContentPresented(
                        automationMode: launchConfiguration.automationMode
                            || launchConfiguration.acceptanceMode
                    )
                    // Acceptance and automation never touch tokens or sync.
                    if !launchConfiguration.usesDeterministicDemoData {
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
                .disabled(!syncController.canSync || launchConfiguration.acceptanceMode)
                .help(!syncController.canSync ? "Connect a logbook to sync" : "Sync Concept2 Logbook")
                .accessibilityHint(!syncController.canSync ? "Requires logbook connection" : "Syncs logbook with Concept2")

                Button("Reload Workout Library") {
                    Task {
                        await syncController.loadCachedWorkouts(into: library)
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(syncController.isLoading || launchConfiguration.acceptanceMode)
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

    @ViewBuilder
    private var rootContent: some View {
        if let acceptance = launchConfiguration.acceptanceConfiguration {
            ReplayAcceptanceHarnessView(configuration: acceptance)
        } else {
            ContentView(library: library)
        }
    }

    private var windowMinimumWidth: CGFloat {
        if let acceptance = launchConfiguration.acceptanceConfiguration {
            return CGFloat(acceptance.windowWidth)
        }
        return 1_000
    }

    private var windowMinimumHeight: CGFloat {
        if let acceptance = launchConfiguration.acceptanceConfiguration {
            return CGFloat(acceptance.windowHeight)
        }
        return 680
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
