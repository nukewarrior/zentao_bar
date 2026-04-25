import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            UpdateReminderService.shared.start()
            await AppState.shared.bootstrap()
        }
    }
}

@main
struct ZentaoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var preferences = PreferencesStore.shared
    @StateObject private var updateReminder = UpdateReminderService.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .environmentObject(updateReminder)
        } label: {
            Text(appState.formattedTotal)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .environmentObject(updateReminder)
        }

        Window("关于 ZentaoBar", id: "about") {
            AboutView()
                .environmentObject(appState)
                .environmentObject(preferences)
                .environmentObject(updateReminder)
        }
    }
}
