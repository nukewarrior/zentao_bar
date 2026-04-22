import AppKit
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
    private let refreshCacheInterval: TimeInterval = 60

    private var didBootstrap = false

    init(
        configStore: AppConfigurationStore = AppConfigurationStore(),
        tokenStore: KeychainTokenStore = KeychainTokenStore(),
        apiClient: ZentaoAPIClient = ZentaoAPIClient()
    ) {
        self.configStore = configStore
        self.tokenStore = tokenStore
        self.apiClient = apiClient
        self.lastUpdatedAt = configStore.loadLastRefreshDate()
    }

    var config: AppConfig? {
        configStore.load()
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
            return
        }

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
            }

            let newConfig = AppConfig(baseURL: baseURL, account: account)
            try configStore.save(newConfig)
            try tokenStore.saveToken(token, baseURL: baseURL, account: account)
            await refresh(force: true)
            return true
        } catch {
            loadState = .authRequired
            errorMessage = friendlyErrorMessage(error)
            return false
        }
    }

    func refresh(force: Bool = true) async {
        guard let config, let token = currentToken else {
            loadState = .authRequired
            return
        }

        if !force,
           let lastUpdatedAt,
           Date().timeIntervalSince(lastUpdatedAt) < refreshCacheInterval,
           !taskWorks.isEmpty {
            loadState = .loaded
            return
        }

        let hadData = !taskWorks.isEmpty
        loadState = .loading
        errorMessage = nil

        do {
            let user = try await apiClient.fetchCurrentUser(
                baseURL: config.baseURL,
                token: token
            )
            let tasks = try await apiClient.fetchAssignedTasks(
                baseURL: config.baseURL,
                token: token
            )

            let today = Self.todayString()
            let apiClient = self.apiClient
            let baseURL = config.baseURL
            var aggregates: [Int: TaskWork] = [:]

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
                        if aggregates[task.id] == nil {
                            aggregates[task.id] = TaskWork(
                                id: task.id,
                                name: task.name,
                                url: "\(baseURL)/task-\(task.id).html",
                                totalConsumed: 0
                            )
                        }

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
            loadState = sorted.isEmpty ? .empty : .loaded
        } catch {
            if let apiError = error as? ZentaoAPIError,
               case .unauthorized = apiError {
                tokenStore.deleteToken(baseURL: config.baseURL, account: config.account)
                loadState = .authRequired
            } else if hadData {
                loadState = .loaded
            } else {
                loadState = .failed(friendlyErrorMessage(error))
            }

            errorMessage = friendlyErrorMessage(error)
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
    }

    func openTask(_ task: TaskWork) {
        openURL(task.url)
    }

    func openZentaoHome() {
        guard let config else { return }
        openURL(config.baseURL)
    }

    func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
