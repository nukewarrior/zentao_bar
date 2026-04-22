import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            await AppState.shared.bootstrap()
        }
    }
}

@main
struct ZentaoBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuPanelView()
                .environmentObject(appState)
        } label: {
            Text(appState.formattedTotal)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        Window("关于 ZentaoBar", id: "about") {
            AboutView()
                .environmentObject(appState)
        }
    }
}
