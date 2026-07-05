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
                .onAppear {
                    if !preferences.demoModeEnabled {
                        library.clearData()
                    }
                }
                .onChange(of: preferences.demoModeEnabled) { _, enabled in
                    if enabled && library.isEmpty {
                        library.reloadDemoData()
                    } else if !enabled {
                        library.clearData()
                    }
                }
        }
        .commands {
            SidebarCommands()
            CommandMenu("Workout") {
                Button("Reload Demo Library") {
                    guard preferences.demoModeEnabled else { return }
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

