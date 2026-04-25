import AppKit
import Combine
import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

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
        DebugLogger.log(
            "AppState initialized; build=\(AppMetadata.current.buildConfiguration), logFile=\(DebugLogger.logFilePath)"
        )
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
        DebugLogger.log("Bootstrap started")

        guard config != nil, currentToken != nil else {
            DebugLogger.log("Bootstrap requires authentication; missing config or token")
            loadState = .authRequired
            reconfigureAutoRefresh()
            return
        }

        reconfigureAutoRefresh()
        await refresh(force: false)
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
        DebugLogger.log("Login attempt started for account=\(account), baseURL=\(baseURL)")

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
            }

            let newConfig = AppConfig(baseURL: baseURL, account: account)
            try configStore.save(newConfig)
            try tokenStore.saveToken(token, baseURL: baseURL, account: account)
            DebugLogger.log("Login succeeded for account=\(account)")
            reconfigureAutoRefresh()
            await refresh(force: true)
            return true
        } catch {
            loadState = .authRequired
            errorMessage = friendlyErrorMessage(error)
            reconfigureAutoRefresh()
            DebugLogger.log("Login failed for account=\(account): \(friendlyErrorMessage(error))")
            return false
        }
    }

    func refresh(force: Bool = true) async {
        guard let config, let token = currentToken else {
            DebugLogger.log("Refresh skipped; missing config or token")
            loadState = .authRequired
            reconfigureAutoRefresh()
            return
        }

        if isRefreshingInFlight {
            DebugLogger.log("Refresh skipped because another refresh is already running")
            return
        }

        if !force,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < preferences.autoRefreshInterval.seconds,
           !taskWorks.isEmpty {
            DebugLogger.log("Refresh skipped due to cache; taskCount=\(taskWorks.count)")
            loadState = .loaded
            return
        }

        let hadData = !taskWorks.isEmpty
        isRefreshingInFlight = true
        loadState = .loading
        errorMessage = nil
        DebugLogger.log("Refresh started; force=\(force), hadData=\(hadData), baseURL=\(config.baseURL)")

        defer {
            isRefreshingInFlight = false
        }

        do {
            let user = try await apiClient.fetchCurrentUser(
                baseURL: config.baseURL,
                token: token
            )
            let tasks = try await fetchTasksForCurrentUser(
                baseURL: config.baseURL,
                token: token,
                account: user.account
            )

            let today = Self.todayString()
            let apiClient = self.apiClient
            let baseURL = config.baseURL
            var aggregates: [Int: TaskWork] = Dictionary(
                uniqueKeysWithValues: tasks.map { task in
                    (
                        task.id,
                        TaskWork(
                            id: task.id,
                            name: task.name,
                            url: "\(baseURL)/task-view-\(task.id).html",
                            totalConsumed: 0
                        )
                    )
                }
            )

            try await withThrowingTaskGroup(of: (ZentaoTask, [ZentaoEstimate]).self) { group in
                for task in tasks {
                    group.addTask {
                        let estimates = try await apiClient.fetchEstimates(
                            baseURL: baseURL,
                            token: token,
                            taskID: task.id
                        )
                        return (task, estimates)
                    }
                }

                for try await (task, estimates) in group {
                    for estimate in estimates where estimate.account == user.account && estimate.date == today {
                        aggregates[task.id]?.totalConsumed += estimate.consumed
                    }
                }
            }

            let sorted = aggregates.values.sorted { left, right in
                if left.totalConsumed == right.totalConsumed {
                    return left.name.localizedCompare(right.name) == .orderedAscending
                }

                return left.totalConsumed > right.totalConsumed
            }

            taskWorks = sorted
            totalConsumed = sorted.reduce(0) { $0 + $1.totalConsumed }
            lastUpdatedAt = Date()
            configStore.saveLastRefreshDate(lastUpdatedAt)
            loadState = tasks.isEmpty ? .empty : .loaded
            DebugLogger.log(
                "Refresh succeeded; user=\(user.account), taskCount=\(sorted.count), totalConsumed=\(totalConsumed)"
            )
        } catch {
            if let apiError = error as? ZentaoAPIError,
               case .unauthorized = apiError {
                tokenStore.deleteToken(baseURL: config.baseURL, account: config.account)
                loadState = .authRequired
                reconfigureAutoRefresh()
            } else if hadData {
                loadState = .loaded
            } else {
                loadState = .failed(friendlyErrorMessage(error))
            }

            errorMessage = friendlyErrorMessage(error)
            DebugLogger.log("Refresh failed: \(friendlyErrorMessage(error))")
        }
    }

    func logout() {
        guard let config else {
            loadState = .authRequired
            return
        }

        tokenStore.deleteToken(baseURL: config.baseURL, account: config.account)
        taskWorks = []
        totalConsumed = 0
        errorMessage = nil
        loadState = .authRequired
        reconfigureAutoRefresh()
        DebugLogger.log("Logout completed for account=\(config.account)")
    }

    func openTask(_ task: TaskWork) {
        openURL(task.url)
    }

    func openZentaoHome() {
        guard let config else { return }
        openURL(config.baseURL)
    }

    func quitApplication() {
        DebugLogger.log("Application terminating by user request")
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
            DebugLogger.log("Auto refresh disabled")
            return
        }

        guard config != nil, currentToken != nil else {
            DebugLogger.log("Auto refresh not scheduled because authentication is missing")
            return
        }

        let interval = preferences.autoRefreshInterval.seconds
        DebugLogger.log("Auto refresh scheduled every \(Int(interval)) seconds")

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

        DebugLogger.log("Auto refresh tick fired")
        await refresh(force: true)
    }

    private func fetchTasksForCurrentUser(
        baseURL: String,
        token: String,
        account: String
    ) async throws -> [ZentaoTask] {
        let assignedTasks: [ZentaoTask]
        do {
            assignedTasks = try await apiClient.fetchAssignedTasks(
                baseURL: baseURL,
                token: token
            )
            DebugLogger.log("Loaded assigned tasks from /tasks?assignedTo=me; count=\(assignedTasks.count)")
        } catch let error as ZentaoAPIError {
            guard case let .requestFailed(statusCode, message) = error,
                  statusCode == 403,
                  (message?.localizedCaseInsensitiveContains("Access not allowed") ?? false) else {
                throw error
            }

            DebugLogger.log("Falling back to legacy my-work task entry due to restricted /tasks endpoint")

            do {
                assignedTasks = try await apiClient.fetchLegacyAssignedTasks(
                    baseURL: baseURL,
                    token: token
                )
            } catch {
                DebugLogger.log("Legacy my-work fallback failed: \(friendlyErrorMessage(error))")

                DebugLogger.log("Falling back to execution traversal due to restricted /tasks endpoint")

                do {
                    assignedTasks = try await fetchTasksViaExecutions(
                        baseURL: baseURL,
                        token: token,
                        account: account
                    )
                } catch {
                    DebugLogger.log("Execution traversal fallback failed: \(friendlyErrorMessage(error))")
                    DebugLogger.log("Falling back to project/execution traversal as final recovery path")
                    assignedTasks = try await fetchTasksViaProjectExecutions(
                        baseURL: baseURL,
                        token: token,
                        account: account
                    )
                }
            }
        }

        // 补充获取我参与过的任务（包括已关闭的），与 assignedTo=me 的任务合并去重
        let involvedTasks = (try? await apiClient.fetchMyInvolvedTasks(
            baseURL: baseURL,
            token: token
        )) ?? []
        DebugLogger.log("Loaded involved tasks from /my-contribute-task-myInvolved; count=\(involvedTasks.count)")

        // 合并去重：优先保留 assignedTo=me 的任务
        var mergedTasks: [Int: ZentaoTask] = [:]
        for task in assignedTasks {
            mergedTasks[task.id] = task
        }
        for task in involvedTasks {
            if mergedTasks[task.id] == nil {
                mergedTasks[task.id] = task
            }
        }

        let result = mergedTasks.values.sorted { $0.id < $1.id }
        DebugLogger.log("Merged tasks: assigned=\(assignedTasks.count), involved=\(involvedTasks.count), total=\(result.count)")
        return result
    }

    private func fetchTasksViaExecutions(
        baseURL: String,
        token: String,
        account: String
    ) async throws -> [ZentaoTask] {
        let executions = try await apiClient.fetchExecutions(
            baseURL: baseURL,
            token: token
        )
        DebugLogger.log("Loaded executions for fallback; count=\(executions.count)")

        let apiClient = self.apiClient
        var uniqueTasks: [Int: ZentaoTask] = [:]

        try await withThrowingTaskGroup(of: [ZentaoTask].self) { group in
            for execution in executions {
                group.addTask {
                    try await apiClient.fetchExecutionTasks(
                        baseURL: baseURL,
                        token: token,
                        executionID: execution.id,
                        status: "assignedtome"
                    )
                }
            }

            for try await tasks in group {
                for task in tasks where task.assignedTo == account || task.assignedTo == nil {
                    uniqueTasks[task.id] = task
                }
            }
        }

        let result = uniqueTasks.values.sorted { left, right in
            left.id < right.id
        }
        DebugLogger.log("Filtered execution fallback tasks assigned to \(account); count=\(result.count)")
        return result
    }

    private func fetchTasksViaProjectExecutions(
        baseURL: String,
        token: String,
        account: String
    ) async throws -> [ZentaoTask] {
        let projects = try await apiClient.fetchProjects(
            baseURL: baseURL,
            token: token
        )
        DebugLogger.log("Loaded projects for fallback; count=\(projects.count)")

        var executionIDs = Set<Int>()

        for project in projects {
            let executions = try await apiClient.fetchProjectExecutions(
                baseURL: baseURL,
                token: token,
                projectID: project.id
            )

            for execution in executions {
                executionIDs.insert(execution.id)
            }
        }

        DebugLogger.log("Loaded executions for fallback; uniqueCount=\(executionIDs.count)")

        var uniqueTasks: [Int: ZentaoTask] = [:]
        let apiClient = self.apiClient

        try await withThrowingTaskGroup(of: [ZentaoTask].self) { group in
            for executionID in executionIDs {
                group.addTask {
                    try await apiClient.fetchExecutionTasks(
                        baseURL: baseURL,
                        token: token,
                        executionID: executionID
                    )
                }
            }

            for try await tasks in group {
                for task in tasks where task.assignedTo == account {
                    uniqueTasks[task.id] = task
                }
            }
        }

        let result = uniqueTasks.values.sorted { left, right in
            left.id < right.id
        }
        DebugLogger.log("Filtered fallback tasks assigned to \(account); count=\(result.count)")
        return result
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }

        return error.localizedDescription
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
