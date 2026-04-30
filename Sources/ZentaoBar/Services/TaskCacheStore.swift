import Foundation

enum TaskCacheStore {
    private static func cacheKey(userID: Int?) -> String {
        "taskCache_\(userID ?? 0)"
    }

    static func loadTaskWorks(defaults: UserDefaults, userID: Int?) -> [TaskWork]? {
        let key = cacheKey(userID: userID)
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode([TaskWork].self, from: data)
    }

    static func saveTaskWorks(_ taskWorks: [TaskWork], defaults: UserDefaults, userID: Int?) {
        guard !taskWorks.isEmpty else { return }
        let key = cacheKey(userID: userID)
        if let data = try? JSONEncoder().encode(taskWorks) {
            defaults.set(data, forKey: key)
        }
    }

    static func clearTaskWorks(defaults: UserDefaults, userID: Int?) {
        let key = cacheKey(userID: userID)
        defaults.removeObject(forKey: key)
    }
}
