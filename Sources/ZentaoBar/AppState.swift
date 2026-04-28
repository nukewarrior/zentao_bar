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

        guard config != nil, currentToken != nil else {
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

            let newConfig = AppConfig(baseURL: baseURL, account: account)
            try configStore.save(newConfig)
            try tokenStore.saveToken(token, baseURL: baseURL, account: account)
            try tokenStore.savePassword(password, baseURL: baseURL, account: account)
            reconfigureAutoRefresh()
            await refresh(force: true)
            return true
        } catch {
            loadState = .authRequired
            errorMessage = friendlyErrorMessage(error)
            reconfigureAutoRefresh()
            return false
        }
    }

    func refresh(force: Bool = true) async {
        guard let config, let token = currentToken else {
            loadState = .authRequired
            reconfigureAutoRefresh()
            return
        }

        if isRefreshingInFlight {
            return
        }

        if !force,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < preferences.autoRefreshInterval.seconds,
           !taskWorks.isEmpty {
            loadState = .loaded
            return
        }

        let hadData = !taskWorks.isEmpty
        isRefreshingInFlight = true
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

            let involvedTasks = (try? await apiClient.fetchMyInvolvedTasks(
                baseURL: config.baseURL,
                token: token
            )) ?? []

            let allTasks = mergeTasks(current: currentTasks, involved: involvedTasks)

            taskWorks = allTasks.map { task in
                let work = TaskWork(
                    id: task.id,
                    name: task.name,
                    url: "\(config.baseURL)/task-view-\(task.id).html",
                    totalConsumed: task.consumed ?? 0
                )
                DebugLogger.log("Task work: id=\(task.id), name=\(task.name), consumed=\(task.consumed ?? 0)h, url=\(work.url)")
                return work
            }

            totalConsumed = taskWorks.reduce(0) { $0 + $1.totalConsumed }
            lastUpdatedAt = Date()
            configStore.saveLastRefreshDate(lastUpdatedAt)
            loadState = taskWorks.isEmpty ? .empty : .loaded
        } catch {
            if let apiError = error as? ZentaoAPIError,
               case .unauthorized = apiError {
                if await attemptReLogin() {
                    await refresh(force: true)
                    return
                } else {
                    tokenStore.deleteToken(baseURL: config.baseURL, account: config.account)
                    loadState = .authRequired
                    reconfigureAutoRefresh()
                }
            } else if hadData {
                loadState = .loaded
            } else {
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

    private func mergeTasks(current: [ZentaoTaskItem], involved: [ZentaoTaskItem]) -> [ZentaoTaskItem] {
        var merged: [Int: ZentaoTaskItem] = [:]

        for task in current {
            merged[task.id] = task
        }

        for task in involved {
            if merged[task.id] == nil {
                merged[task.id] = task
            }
        }

        return merged.values.sorted { $0.id < $1.id }
    }

    private func friendlyErrorMessage(_ error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}