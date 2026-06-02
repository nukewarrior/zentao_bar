import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    private enum TaskDetailFetchResult: Sendable {
        case success(todayConsumed: Double, detailTask: ZentaoTaskItem?)
        case failure(message: String)
    }

    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var taskWorks: [TaskWork] = []
    @Published private(set) var totalConsumed: Double = 0
    @Published private(set) var lastUpdatedAt: Date?
    @Published var errorMessage: String?

    private let configStore: AppConfigurationStore
    private let tokenStore: KeychainTokenStore
    private let apiClient: ZentaoAPIClient
    private let preferences: PreferencesStore

    private var didBootstrap = false
    private var cancellables = Set<AnyCancellable>()
    private var autoRefreshTask: Task<Void, Never>?
    private var isRefreshingInFlight = false

    init(
        configStore: AppConfigurationStore = AppConfigurationStore(),
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        apiClient: ZentaoAPIClient = ZentaoAPIClient(),
        preferences: PreferencesStore = .shared
    ) {
        self.configStore = configStore
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.preferences = preferences
        self.lastUpdatedAt = configStore.loadLastRefreshDate()
        let lastUpdatedDescription = self.lastUpdatedAt.map { String(describing: $0) } ?? "nil"
        DebugLogger.log("AppState init: lastUpdatedAt=\(lastUpdatedDescription)")
        restoreCachedTaskWorks()
        observePreferences()
    }

    var config: AppConfig? {
        configStore.load()
    }

    var isLoggedIn: Bool {
        config != nil && currentToken != nil
    }

    var currentTaskCount: Int {
        taskWorks.count
    }

    var refreshIntervalDescription: String {
        preferences.autoRefreshInterval.title
    }

    var refreshPolicyDescription: String {
        if preferences.autoRefreshEnabled {
            return "后台每 \(preferences.autoRefreshInterval.title) 自动刷新，间隔同时作为缓存有效期"
        }
        return "后台自动刷新已关闭，缓存有效期为 \(preferences.autoRefreshInterval.title)"
    }

    var formattedTotal: String {
        let total = totalConsumed
        if total.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(total))"
        }
        return String(format: "%.1f", total)
    }

    var formattedTotalWithUnit: String {
        "\(formattedTotal)h"
    }

    var lastUpdatedText: String {
        guard let lastUpdatedAt else {
            return "尚未刷新"
        }
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "上次更新于 \(formatter.string(from: lastUpdatedAt))"
    }

    var needsAuthentication: Bool {
        config == nil || currentToken == nil || loadState == .authRequired
    }

    private var currentToken: String? {
        guard let config else { return nil }
        return tokenStore.loadToken(baseURL: config.baseURL, account: config.account)
    }

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true

        DebugLogger.log("bootstrap: start")

        guard config != nil, currentToken != nil else {
            DebugLogger.log("bootstrap: auth required")
            loadState = .authRequired
            reconfigureAutoRefresh()
            return
        }

        DebugLogger.log("bootstrap: reconfigure auto refresh and start immediate background refresh")
        reconfigureAutoRefresh()
        Task { @MainActor [weak self] in
            await self?.refresh(force: true)
        }
    }

    func login(baseURL rawBaseURL: String, account rawAccount: String, password: String) async -> Bool {
        let account = rawAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else {
            errorMessage = "请输入账号。"
            loadState = .authRequired
            return false
        }

        guard !password.isEmpty else {
            errorMessage = "请输入密码。"
            loadState = .authRequired
            return false
        }

        guard let baseURL = apiClient.normalizedBaseURL(from: rawBaseURL) else {
            errorMessage = "地址格式错误，请输入完整的禅道地址。"
            loadState = .authRequired
            return false
        }

        loadState = .loading
        errorMessage = nil

        do {
            let token = try await apiClient.fetchToken(
                baseURL: baseURL,
                account: account,
                password: password
            )
            let user = try await apiClient.fetchCurrentUser(
                baseURL: baseURL,
                token: token
            )

            if user.account != account {
                errorMessage = "登录成功，但当前接口返回账号与输入账号不一致。"
            }

            let oldConfig = config
            if let oldConfig,
               oldConfig.baseURL != baseURL || oldConfig.account != account {
                tokenStore.deleteToken(baseURL: oldConfig.baseURL, account: oldConfig.account)
                tokenStore.deletePassword(baseURL: oldConfig.baseURL, account: oldConfig.account)
            }

            let newConfig = AppConfig(baseURL: baseURL, account: account, userID: user.id)
            // Keychain 先保存，UserDefaults 后保存 — Keychain 失败则不污染 config
            try tokenStore.saveToken(token, baseURL: baseURL, account: account)
            try tokenStore.savePassword(password, baseURL: baseURL, account: account)
            try configStore.save(newConfig)
            reconfigureAutoRefresh()
            await refresh(force: true, bypassInFlight: true)
            return true
        } catch {
            loadState = .authRequired
            errorMessage = friendlyErrorMessage(error)
            reconfigureAutoRefresh()
            return false
        }
    }

    func refresh(force: Bool = true, bypassInFlight: Bool = false) async {
        guard let config, let token = currentToken else {
            DebugLogger.log("refresh: skipped, auth required")
            loadState = .authRequired
            reconfigureAutoRefresh()
            return
        }

        if !bypassInFlight, isRefreshingInFlight {
            DebugLogger.log("refresh: skipped, already in flight")
            return
        }

        // 立即设置标志位，消除 check-then-set 之间的竞态窗口
        if !bypassInFlight {
            isRefreshingInFlight = true
        }

        if !force,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < preferences.autoRefreshInterval.seconds,
           !taskWorks.isEmpty {
            DebugLogger.log("refresh: reuse recent in-memory tasks, count=\(taskWorks.count)")
            loadState = .loaded
            if !bypassInFlight { isRefreshingInFlight = false }
            return
        }

        let hadData = !taskWorks.isEmpty
        DebugLogger.log("refresh: start, force=\(force), hadData=\(hadData), currentCount=\(taskWorks.count)")
        loadState = .loading
        errorMessage = nil

        defer {
            isRefreshingInFlight = false
        }

        do {
            let currentTasks = try await apiClient.fetchAssignedTasks(
                baseURL: config.baseURL,
                token: token
            )

            let dynamicTasksToday = (try? await apiClient.fetchTodayDynamic(
                baseURL: config.baseURL,
                token: token,
                userID: config.userID ?? 0
            ))

            var allTasks = currentTasks.sorted { $0.id < $1.id }

            // 补充今日有动态但不在指派/参与列表中的任务（如已完成的）
            let dynamicTaskIDsToday = Set(dynamicTasksToday?.taskIDsWithActionToday ?? [])
            if let dynamicTasksToday {
                DebugLogger.log("refresh: today dynamic parsed, recTotal=\(dynamicTasksToday.recTotal), taskIDs=\(dynamicTaskIDsToday.sorted())")
            } else {
                DebugLogger.log("refresh: today dynamic unavailable")
            }

            if let dynamicTasksToday {
                let existingIDs = Set(allTasks.map { $0.id })
                for taskID in dynamicTaskIDsToday {
                    if !existingIDs.contains(taskID) {
                        let name = dynamicTasksToday.dateGroups.values
                            .flatMap { $0 }
                            .first { $0.objectID == taskID && $0.objectType == "task" }?
                            .objectName ?? "任务 #\(taskID)"
                        allTasks.append(ZentaoTaskItem(id: taskID, name: name))
                    }
                }
            }

            let previousTaskWorksByID = Dictionary(uniqueKeysWithValues: taskWorks.map { ($0.id, $0) })

            let taskDetails = await withTaskGroup(of: (Int, TaskDetailFetchResult).self) { group in
                for task in allTasks {
                    group.addTask {
                        do {
                            let detail = try await Self.fetchTaskDetailWithRetry(
                                apiClient: self.apiClient,
                                baseURL: config.baseURL,
                                token: token,
                                task: task
                            )
                            return (task.id, .success(todayConsumed: detail.todayConsumed(), detailTask: detail.task))
                        } catch {
                            let message = error.localizedDescription
                            DebugLogger.log("refresh: fetch task detail failed, taskID=\(task.id), name=\(task.name), error=\(message)")
                            return (task.id, .failure(message: message))
                        }
                    }
                }

                var results: [Int: TaskDetailFetchResult] = [:]
                for await (taskID, result) in group {
                    results[taskID] = result
                }
                return results
            }

            let detailSuccessCount = taskDetails.values.reduce(0) { count, result in
                if case .success = result {
                    return count + 1
                }
                return count
            }
            let detailFailureCount = taskDetails.values.reduce(0) { count, result in
                if case .failure = result {
                    return count + 1
                }
                return count
            }
            var fallbackHitCount = 0
            var fallbackMissCount = 0

            taskWorks = allTasks.compactMap { task in
                let detail = taskDetails[task.id]
                let resolvedTask: ZentaoTaskItem
                let todayConsumed: Double

                switch detail {
                case let .success(detailTodayConsumed, detailTask):
                    resolvedTask = detailTask ?? task
                    todayConsumed = detailTodayConsumed
                case let .failure(message):
                    resolvedTask = task
                    if let cachedTaskWork = previousTaskWorksByID[task.id] {
                        todayConsumed = cachedTaskWork.totalConsumed
                        fallbackHitCount += 1
                        DebugLogger.log("refresh: task detail fallback hit, taskID=\(task.id), name=\(task.name), cachedConsumed=\(cachedTaskWork.totalConsumed), error=\(message)")
                    } else {
                        todayConsumed = 0
                        fallbackMissCount += 1
                        DebugLogger.log("refresh: task detail fallback miss, taskID=\(task.id), name=\(task.name), error=\(message)")
                    }
                case .none:
                    resolvedTask = task
                    if let cachedTaskWork = previousTaskWorksByID[task.id] {
                        todayConsumed = cachedTaskWork.totalConsumed
                        fallbackHitCount += 1
                        DebugLogger.log("refresh: task detail missing result fallback hit, taskID=\(task.id), name=\(task.name), cachedConsumed=\(cachedTaskWork.totalConsumed)")
                    } else {
                        todayConsumed = 0
                        fallbackMissCount += 1
                        DebugLogger.log("refresh: task detail missing result fallback miss, taskID=\(task.id), name=\(task.name)")
                    }
                }

                guard shouldDisplayTask(
                    resolvedTask,
                    todayConsumed: todayConsumed,
                    hasActionToday: dynamicTaskIDsToday.contains(resolvedTask.id)
                ) else {
                    DebugLogger.log("refresh: hide stale terminal task id=\(resolvedTask.id), status=\(resolvedTask.status)")
                    return nil
                }

                return TaskWork(
                    id: resolvedTask.id,
                    name: resolvedTask.name,
                    url: "\(config.baseURL)/task-view-\(resolvedTask.id).html",
                    deadline: resolvedTask.deadline,
                    status: resolvedTask.status,
                    totalConsumed: todayConsumed,
                    isPlaceholder: resolvedTask.isPlaceholder
                )
            }.sorted { left, right in
                let lhs = deadlinePriority(left)
                let rhs = deadlinePriority(right)
                if lhs != rhs { return lhs < rhs }
                return left.totalConsumed > right.totalConsumed
            }

            DebugLogger.log("refresh: task detail summary, total=\(allTasks.count), success=\(detailSuccessCount), failed=\(detailFailureCount), fallbackHit=\(fallbackHitCount), fallbackMiss=\(fallbackMissCount)")
            totalConsumed = taskWorks.reduce(0) { $0 + $1.totalConsumed }
            lastUpdatedAt = Date()
            configStore.saveLastRefreshDate(lastUpdatedAt)
            TaskCacheStore.saveTaskWorks(taskWorks, defaults: .standard, userID: config.userID)
            DebugLogger.log("refresh: success, taskCount=\(taskWorks.count), totalConsumed=\(formattedTotal)")
            loadState = taskWorks.isEmpty ? .empty : .loaded
        } catch {
            if let apiError = error as? ZentaoAPIError,
               case .unauthorized = apiError {
                DebugLogger.log("refresh: unauthorized, attempting relogin")
                if await attemptReLogin() {
                    return
                } else {
                    tokenStore.deleteToken(baseURL: config.baseURL, account: config.account)
                    DebugLogger.log("refresh: relogin failed, auth required")
                    loadState = .authRequired
                    reconfigureAutoRefresh()
                }
            } else if hadData {
                DebugLogger.log("refresh: failed with stale data preserved, error=\(friendlyErrorMessage(error))")
                loadState = .loaded
            } else {
                DebugLogger.log("refresh: failed without data, error=\(friendlyErrorMessage(error))")
                loadState = .failed(friendlyErrorMessage(error))
            }

            errorMessage = friendlyErrorMessage(error)
        }
    }

    private func attemptReLogin() async -> Bool {
        guard let config else { return false }
        guard let password = tokenStore.loadPassword(baseURL: config.baseURL, account: config.account) else {
            return false
        }

        return await login(baseURL: config.baseURL, account: config.account, password: password)
    }

    func logout() {
        guard let config else {
            loadState = .authRequired
            return
        }

        DebugLogger.log("logout: clear token and task cache")
        tokenStore.deleteToken(baseURL: config.baseURL, account: config.account)
        tokenStore.deletePassword(baseURL: config.baseURL, account: config.account)
        taskWorks = []
        totalConsumed = 0
        errorMessage = nil
        loadState = .authRequired
        reconfigureAutoRefresh()
    }

    func openTask(_ task: TaskWork) {
        openURL(task.url)
    }

    func openZentaoHome() {
        guard let config else { return }
        openURL(config.baseURL)
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }

    func baseURLPlaceholder() -> String {
        config?.baseURL ?? "http://host:port/zentao"
    }

    func accountPlaceholder() -> String {
        config?.account ?? ""
    }

    private func openURL(_ rawURL: String) {
        guard let url = URL(string: rawURL) else { return }
        NSWorkspace.shared.open(url)
    }

    private func observePreferences() {
        preferences.$autoRefreshEnabled
            .combineLatest(preferences.$autoRefreshInterval)
            .sink { [weak self] _, _ in
                Task { @MainActor [weak self] in
                    self?.reconfigureAutoRefresh()
                }
            }
            .store(in: &cancellables)
    }

    private func reconfigureAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil

        guard preferences.autoRefreshEnabled else {
            return
        }

        guard config != nil, currentToken != nil else {
            return
        }

        let interval = preferences.autoRefreshInterval.seconds

        autoRefreshTask = Task { [weak self] in
            guard let self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }

                if Task.isCancelled {
                    break
                }

                await self.performAutoRefreshTick()
            }
        }
    }

    private func performAutoRefreshTick() async {
        guard preferences.autoRefreshEnabled else { return }
        guard config != nil, currentToken != nil else { return }

        await refresh(force: true)
    }

    private func deadlinePriority(_ task: TaskWork) -> Int {
        switch task.deadlineType {
        case .overdue: return 0
        case .dueToday: return 1
        case .none: return 2
        }
    }

    nonisolated private static func fetchTaskDetailWithRetry(
        apiClient: ZentaoAPIClient,
        baseURL: String,
        token: String,
        task: ZentaoTaskItem,
        maxAttempts: Int = 3
    ) async throws -> ZentaoTaskDetailData {
        var attempt = 1

        while true {
            do {
                return try await apiClient.fetchTaskDetail(
                    baseURL: baseURL,
                    token: token,
                    taskID: task.id
                )
            } catch {
                guard attempt < maxAttempts, isRetryableTaskDetailError(error) else {
                    throw error
                }

                let nextAttempt = attempt + 1
                let delayNanoseconds = UInt64(attempt) * 500_000_000
                DebugLogger.log("refresh: retry task detail, taskID=\(task.id), name=\(task.name), nextAttempt=\(nextAttempt), maxAttempts=\(maxAttempts), error=\(error.localizedDescription)")
                try await Task.sleep(nanoseconds: delayNanoseconds)
                attempt = nextAttempt
            }
        }
    }

    nonisolated private static func isRetryableTaskDetailError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            return isRetryableURLErrorCode(urlError.code)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return isRetryableURLErrorCode(URLError.Code(rawValue: nsError.code))
        }

        return false
    }

    nonisolated private static func isRetryableURLErrorCode(_ code: URLError.Code) -> Bool {
        switch code {
        case .timedOut,
             .networkConnectionLost,
             .cannotConnectToHost,
             .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private func shouldDisplayTask(
        _ task: ZentaoTaskItem,
        todayConsumed: Double,
        hasActionToday: Bool
    ) -> Bool {
        if !isTerminalTask(task) {
            return true
        }

        return todayConsumed > 0 || hasActionToday
    }

    private func isTerminalTask(_ task: ZentaoTaskItem) -> Bool {
        Self.terminalTaskStatuses.contains(task.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }

    private static let terminalTaskStatuses: Set<String> = [
        "done",
        "closed",
        "cancel",
        "cancelled",
        "canceled"
    ]

    private func restoreCachedTaskWorks() {
        guard let config, currentToken != nil else { return }
        guard let cachedTaskWorks = TaskCacheStore.loadTaskWorks(defaults: .standard, userID: config.userID) else {
            DebugLogger.log("restoreCachedTaskWorks: miss for userID=\(config.userID ?? 0)")
            return
        }

        taskWorks = cachedTaskWorks
        totalConsumed = cachedTaskWorks.reduce(0) { $0 + $1.totalConsumed }
        DebugLogger.log("restoreCachedTaskWorks: hit for userID=\(config.userID ?? 0), count=\(cachedTaskWorks.count)")
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
