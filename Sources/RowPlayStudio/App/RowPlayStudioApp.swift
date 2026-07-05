import AppKit
import RowPlayCore
import SwiftUI

@main
struct RowPlayStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var preferences = AppPreferences()
    @StateObject private var library = WorkoutLibrary.demo()

    var body: some Scene {
        WindowGroup("RowPlay Studio", id: "main") {
            ContentView(library: library)
                .frame(minWidth: 1_000, minHeight: 680)
                .environmentObject(preferences)
        }
        .commands {
            SidebarCommands()
            CommandMenu("Workout") {
                Button("Reload Demo Library") {
                    library.reloadDemoData()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!preferences.demoModeEnabled)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(preferences)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

