import Foundation

enum TaskCacheStore {
    private static func cacheKey(userID: Int?) -> String {
        "taskCache_\(userID ?? 0)"
    }

    static func loadTaskWorks(defaults: UserDefaults, userID: Int?) -> [TaskWork]? {
        let key = cacheKey(userID: userID)
        guard let data = defaults.data(forKey: key) else {
            DebugLogger.log("taskCache load miss: key=\(key)")
            return nil
        }
        guard let taskWorks = try? JSONDecoder().decode([TaskWork].self, from: data) else {
            DebugLogger.log("taskCache load failed: key=\(key), bytes=\(data.count)")
            return nil
        }
        DebugLogger.log("taskCache load hit: key=\(key), count=\(taskWorks.count)")
        return taskWorks
    }

    static func saveTaskWorks(_ taskWorks: [TaskWork], defaults: UserDefaults, userID: Int?) {
        guard !taskWorks.isEmpty else {
            DebugLogger.log("taskCache save skipped: empty task list")
            return
        }
        let key = cacheKey(userID: userID)
        if let data = try? JSONEncoder().encode(taskWorks) {
            defaults.set(data, forKey: key)
            DebugLogger.log("taskCache save success: key=\(key), count=\(taskWorks.count), bytes=\(data.count)")
        } else {
            DebugLogger.log("taskCache save failed: key=\(key), count=\(taskWorks.count)")
        }
    }

    static func clearTaskWorks(defaults: UserDefaults, userID: Int?) {
        let key = cacheKey(userID: userID)
        defaults.removeObject(forKey: key)
        DebugLogger.log("taskCache clear: key=\(key)")
    }
}
