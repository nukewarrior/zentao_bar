import AppKit
import Combine
import Foundation

private struct ReleaseMetadataEntry: Decodable {
    let tag: String
    let version: String
    let publishedAt: String
    let archiveURL: String
    let releasePageURL: String?

    var publishedDate: Date? {
        Self.iso8601Formatter.date(from: publishedAt)
    }

    private static nonisolated(unsafe) let iso8601Formatter = ISO8601DateFormatter()
}

private struct ReleaseEndpointConfiguration {
    let metadataURL: URL
    let repositoryURL: URL

    init?(bundle: Bundle = .main) {
        guard
            let metadataURLString = bundle.object(forInfoDictionaryKey: "ZentaoReleasesMetadataURL") as? String,
            let repositoryURLString = bundle.object(forInfoDictionaryKey: "ZentaoReleasePageBaseURL") as? String,
            let metadataURL = URL(string: metadataURLString),
            let repositoryURL = URL(string: repositoryURLString)
        else {
            return nil
        }

        self.metadataURL = metadataURL
        self.repositoryURL = repositoryURL
    }
}

@MainActor
final class UpdateReminderService: ObservableObject {
    static let shared = UpdateReminderService()

    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var latestAvailableVersion: String?
    @Published private(set) var latestPublishedAt: Date?
    @Published private(set) var latestReleasePageURL: URL?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var statusMessage: String? = "尚未检查新版本"
    @Published private(set) var updateAvailable = false

    private let preferences: PreferencesStore
    private let session: URLSession
    private let configuration: ReleaseEndpointConfiguration?
    private var cancellables = Set<AnyCancellable>()
    private var scheduledCheckTask: Task<Void, Never>?

    init(
        preferences: PreferencesStore = .shared,
        session: URLSession = .shared,
        bundle: Bundle = .main
    ) {
        self.preferences = preferences
        self.session = session
        self.configuration = ReleaseEndpointConfiguration(bundle: bundle)
        observePreferences()
    }

    var releasesMetadataURLDescription: String {
        configuration?.metadataURL.absoluteString ?? "未配置"
    }

    var repositoryURLDescription: String {
        configuration?.repositoryURL.absoluteString ?? "未配置"
    }

    var latestVersionDescription: String {
        latestAvailableVersion ?? "尚未发现新版本"
    }

    var latestPublishedText: String {
        guard let latestPublishedAt else {
            return "未知"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: latestPublishedAt)
    }

    var lastCheckedText: String {
        guard let lastCheckedAt else {
            return "尚未检查"
        }

        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: lastCheckedAt)
    }

    var latestReleasePageDescription: String {
        latestReleasePageURL?.absoluteString ?? fallbackLatestReleasePageURL()?.absoluteString ?? "尚未发现可下载版本"
    }

    var canOpenLatestReleasePage: Bool {
        latestReleasePageURL != nil || fallbackLatestReleasePageURL() != nil
    }

    func start() {
        guard configuration != nil else {
            statusMessage = "版本信息地址未配置，无法检查新版本"
            return
        }

        reconfigureScheduledChecks(runImmediately: preferences.updateChecksEnabled)
    }

    func checkForUpdates(userInitiated: Bool) {
        Task {
            await performCheck(userInitiated: userInitiated)
        }
    }

    func openLatestReleasePage() {
        guard let url = latestReleasePageURL ?? fallbackLatestReleasePageURL() else {
            statusMessage = "未找到可打开的发布页"
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func observePreferences() {
        preferences.$updateChecksEnabled
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] enabled in
                self?.reconfigureScheduledChecks(runImmediately: enabled)
            }
            .store(in: &cancellables)

        preferences.$updateCheckInterval
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.reconfigureScheduledChecks(runImmediately: false)
            }
            .store(in: &cancellables)
    }

    private func reconfigureScheduledChecks(runImmediately: Bool) {
        scheduledCheckTask?.cancel()
        scheduledCheckTask = nil

        guard configuration != nil else {
            statusMessage = "版本信息地址未配置，无法检查新版本"
            return
        }

        guard preferences.updateChecksEnabled else {
            statusMessage = "自动检查新版本已关闭"
            return
        }

        let interval = preferences.updateCheckInterval.seconds
        scheduledCheckTask = Task { [weak self] in
            guard let self else { return }

            if runImmediately {
                await self.performCheck(userInitiated: false)
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    break
                }

                if Task.isCancelled {
                    break
                }

                await self.performCheck(userInitiated: false)
            }
        }
    }

    private func performCheck(userInitiated: Bool) async {
        guard !isCheckingForUpdates else { return }
        guard let configuration else {
            statusMessage = "版本信息地址未配置，无法检查新版本"
            return
        }

        isCheckingForUpdates = true
        statusMessage = userInitiated ? "正在检查新版本..." : "正在后台检查新版本..."
        defer {
            isCheckingForUpdates = false
            lastCheckedAt = Date()
        }

        do {
            let (data, response) = try await session.data(from: configuration.metadataURL)
            guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
                throw UpdateReminderError.invalidResponse
            }

            let decoder = JSONDecoder()
            let releases = try decoder.decode([ReleaseMetadataEntry].self, from: data)

            guard let latestRelease = latestRelease(in: releases) else {
                latestAvailableVersion = nil
                latestPublishedAt = nil
                latestReleasePageURL = fallbackLatestReleasePageURL()
                updateAvailable = false
                statusMessage = "尚未获取到发布信息"
                return
            }

            latestAvailableVersion = latestRelease.version
            latestPublishedAt = latestRelease.publishedDate
            latestReleasePageURL = releasePageURL(for: latestRelease)
            updateAvailable = isNewerVersion(latestRelease.version, than: AppMetadata.current.version)

            if updateAvailable {
                statusMessage = "发现新版本 \(latestRelease.version)，可前往 GitHub 下载"
            } else {
                statusMessage = "当前已是最新版本"
            }
        } catch {
            statusMessage = friendlyErrorMessage(for: error, userInitiated: userInitiated)
        }
    }

    private func latestRelease(in releases: [ReleaseMetadataEntry]) -> ReleaseMetadataEntry? {
        releases.max { lhs, rhs in
            let lhsDate = lhs.publishedDate ?? .distantPast
            let rhsDate = rhs.publishedDate ?? .distantPast
            if lhsDate == rhsDate {
                return lhs.version.compare(rhs.version, options: .numeric) == .orderedAscending
            }
            return lhsDate < rhsDate
        }
    }

    private func isNewerVersion(_ remoteVersion: String, than localVersion: String) -> Bool {
        remoteVersion.compare(localVersion, options: .numeric) == .orderedDescending
    }

    private func releasePageURL(for release: ReleaseMetadataEntry) -> URL? {
        if let releasePageURL = release.releasePageURL, let url = URL(string: releasePageURL) {
            return url
        }

        guard let repositoryURL = configuration?.repositoryURL,
              var components = URLComponents(url: repositoryURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = components.path + "/releases/tag/\(release.tag)"
        return components.url
    }

    private func fallbackLatestReleasePageURL() -> URL? {
        guard let repositoryURL = configuration?.repositoryURL,
              var components = URLComponents(url: repositoryURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = components.path + "/releases/latest"
        return components.url
    }

    private func friendlyErrorMessage(for error: Error, userInitiated: Bool) -> String {
        if let updateError = error as? UpdateReminderError {
            return updateError.localizedDescription
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return userInitiated ? "检查失败，请确认网络连接后重试" : "后台检查失败，将在稍后重试"
        }

        return userInitiated ? "检查失败：\(nsError.localizedDescription)" : "后台检查失败，将在稍后重试"
    }
}

private enum UpdateReminderError: LocalizedError {
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "版本信息服务返回异常，暂时无法检查新版本"
        }
    }
}
