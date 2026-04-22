import Foundation

enum SettingsTab: String, CaseIterable, Identifiable {
    case account
    case general
    case about

    var id: String { rawValue }
}

enum RefreshIntervalOption: Double, CaseIterable, Identifiable {
    case seconds30 = 30
    case seconds60 = 60
    case seconds120 = 120

    var id: Double { rawValue }

    var seconds: TimeInterval { rawValue }

    var title: String {
        "\(Int(rawValue)) 秒"
    }
}

enum UpdateCheckIntervalOption: Double, CaseIterable, Identifiable {
    case seconds30 = 30
    case seconds60 = 60
    case seconds120 = 120

    var id: Double { rawValue }

    var seconds: TimeInterval { rawValue }

    var title: String {
        "\(Int(rawValue)) 秒"
    }

    init?(seconds: TimeInterval) {
        self.init(rawValue: seconds)
    }
}

@MainActor
final class PreferencesStore: ObservableObject {
    static let shared = PreferencesStore()

    @Published var selectedSettingsTab: SettingsTab = .account
    @Published var autoCloseAfterTaskClick: Bool
    @Published var autoCloseAfterActionClick: Bool
    @Published var autoRefreshEnabled: Bool
    @Published var autoRefreshInterval: RefreshIntervalOption

    private let defaults: UserDefaults
    private let autoCloseTaskKey = "preferences.autoCloseAfterTaskClick"
    private let autoCloseActionKey = "preferences.autoCloseAfterActionClick"
    private let autoRefreshEnabledKey = "preferences.autoRefreshEnabled"
    private let autoRefreshIntervalKey = "preferences.autoRefreshInterval"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if defaults.object(forKey: autoCloseTaskKey) == nil {
            defaults.set(true, forKey: autoCloseTaskKey)
        }
        if defaults.object(forKey: autoCloseActionKey) == nil {
            defaults.set(true, forKey: autoCloseActionKey)
        }
        if defaults.object(forKey: autoRefreshEnabledKey) == nil {
            defaults.set(true, forKey: autoRefreshEnabledKey)
        }
        if defaults.object(forKey: autoRefreshIntervalKey) == nil {
            defaults.set(RefreshIntervalOption.seconds60.rawValue, forKey: autoRefreshIntervalKey)
        }
        autoCloseAfterTaskClick = defaults.bool(forKey: autoCloseTaskKey)
        autoCloseAfterActionClick = defaults.bool(forKey: autoCloseActionKey)
        autoRefreshEnabled = defaults.bool(forKey: autoRefreshEnabledKey)

        let storedInterval = defaults.double(forKey: autoRefreshIntervalKey)
        autoRefreshInterval = RefreshIntervalOption(rawValue: storedInterval) ?? .seconds60
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

    func setAutoRefreshEnabled(_ enabled: Bool) {
        autoRefreshEnabled = enabled
        defaults.set(enabled, forKey: autoRefreshEnabledKey)
    }

    func setAutoRefreshInterval(_ interval: RefreshIntervalOption) {
        autoRefreshInterval = interval
        defaults.set(interval.rawValue, forKey: autoRefreshIntervalKey)
    }
}
