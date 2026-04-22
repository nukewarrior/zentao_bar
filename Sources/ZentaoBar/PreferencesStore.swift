import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case account
    case general
    case about

    var id: String { rawValue }
}

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var selectedSettingsTab: SettingsTab = .account
    @Published var autoCloseAfterTaskClick: Bool
    @Published var autoCloseAfterActionClick: Bool

    private let defaults: UserDefaults
    private let autoCloseTaskKey = "preferences.autoCloseAfterTaskClick"
    private let autoCloseActionKey = "preferences.autoCloseAfterActionClick"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: autoCloseTaskKey) == nil {
            defaults.set(true, forKey: autoCloseTaskKey)
        }
        if defaults.object(forKey: autoCloseActionKey) == nil {
            defaults.set(true, forKey: autoCloseActionKey)
        }

        autoCloseAfterTaskClick = defaults.bool(forKey: autoCloseTaskKey)
        autoCloseAfterActionClick = defaults.bool(forKey: autoCloseActionKey)
    }

    func openSettings(tab: SettingsTab) {
        selectedSettingsTab = tab
    }

    func setAutoCloseAfterTaskClick(_ enabled: Bool) {
        autoCloseAfterTaskClick = enabled
        defaults.set(enabled, forKey: autoCloseTaskKey)
    }

    func setAutoCloseAfterActionClick(_ enabled: Bool) {
        autoCloseAfterActionClick = enabled
        defaults.set(enabled, forKey: autoCloseActionKey)
    }
}
