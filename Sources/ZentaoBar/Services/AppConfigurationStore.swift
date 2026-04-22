import Foundation

struct AppConfigurationStore {
    private let defaults: UserDefaults
    private let configKey = "config"
    private let lastRefreshKey = "lastRefreshDate"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppConfig? {
        guard let data = defaults.data(forKey: configKey) else {
            return nil
        }

        return try? JSONDecoder().decode(AppConfig.self, from: data)
    }

    func save(_ config: AppConfig) throws {
        let data = try JSONEncoder().encode(config)
        defaults.set(data, forKey: configKey)
    }

    func clear() {
        defaults.removeObject(forKey: configKey)
        defaults.removeObject(forKey: lastRefreshKey)
    }

    func loadLastRefreshDate() -> Date? {
        defaults.object(forKey: lastRefreshKey) as? Date
    }

    func saveLastRefreshDate(_ date: Date?) {
        defaults.set(date, forKey: lastRefreshKey)
    }
}
