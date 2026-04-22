import Combine
import Foundation
#if canImport(Sparkle)
import Sparkle
#endif

@MainActor
final class SparkleUpdater: ObservableObject {
    static let shared = SparkleUpdater()

    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var isCheckingForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var updateCheckIntervalOption: UpdateCheckIntervalOption = .seconds120
    @Published private(set) var latestAvailableVersion: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var statusMessage: String? = "尚未检查"

#if canImport(Sparkle)
    private let delegateBridge = SparkleUpdaterDelegateBridge()
    private let updaterController: SPUStandardUpdaterController
#endif
    private var cancellables = Set<AnyCancellable>()

    init() {
#if canImport(Sparkle)
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: delegateBridge,
            userDriverDelegate: nil
        )
#endif
        configure()
    }

    var updateFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "未配置"
    }

    var publicKeyStateDescription: String {
        guard let rawKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              !rawKey.isEmpty,
              rawKey != "SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER" else {
            return "未配置"
        }
        return "已配置"
    }

    var updateFeedDescription: String {
        updateFeedURL
    }

    var latestVersionDescription: String {
        latestAvailableVersion ?? "尚未发现新版本"
    }

    var updateCheckIntervalDescription: String {
        updateCheckIntervalOption.title
    }

    var updateIntervalDescription: String {
        updateCheckIntervalOption.title
    }

    var lastCheckedText: String {
        guard let lastCheckedAt else {
            return "尚未检查"
        }

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: lastCheckedAt)
    }

    func start() {
#if canImport(Sparkle)
        do {
            try updaterController.startUpdater()
            statusMessage = "更新服务已启动"
            syncUpdaterPreferences()
        } catch {
            statusMessage = "更新服务启动失败：\(error.localizedDescription)"
        }
#else
        statusMessage = "当前构建未集成 Sparkle"
#endif
    }

    func checkForUpdates(userInitiated: Bool) {
#if canImport(Sparkle)
        isCheckingForUpdates = true
        statusMessage = userInitiated ? "正在检查更新..." : "后台检查更新..."
        updaterController.checkForUpdates(nil)
#else
        statusMessage = "当前构建未集成 Sparkle"
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if canImport(Sparkle)
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
        statusMessage = enabled ? "已开启自动检查更新" : "已关闭自动检查更新"
#else
        statusMessage = "当前构建未集成 Sparkle"
#endif
    }

    func setUpdateCheckInterval(_ option: UpdateCheckIntervalOption) {
#if canImport(Sparkle)
        updaterController.updater.updateCheckInterval = option.seconds
        updateCheckIntervalOption = option
        statusMessage = "检查间隔已更新为 \(option.title)"
#else
        statusMessage = "当前构建未集成 Sparkle"
#endif
    }

    private func configure() {
#if canImport(Sparkle)
        delegateBridge.owner = self
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$canCheckForUpdates)
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .assign(to: &$automaticallyChecksForUpdates)
        updaterController.updater.publisher(for: \.updateCheckInterval)
            .map { UpdateCheckIntervalOption(seconds: $0) ?? .seconds120 }
            .receive(on: RunLoop.main)
            .assign(to: &$updateCheckIntervalOption)
#else
        statusMessage = "当前构建未集成 Sparkle"
#endif
    }

#if canImport(Sparkle)
    private func syncUpdaterPreferences() {
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        updateCheckIntervalOption = UpdateCheckIntervalOption(seconds: updaterController.updater.updateCheckInterval) ?? .seconds120
    }
#endif

#if canImport(Sparkle)
    fileprivate func handleFoundUpdate(_ item: SUAppcastItem) {
        latestAvailableVersion = item.displayVersionString
        statusMessage = "发现新版本 \(item.displayVersionString)"
    }

    fileprivate func handleNoUpdateFound(_ error: Error) {
        let nsError = error as NSError
        if let latestItem = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem {
            latestAvailableVersion = latestItem.displayVersionString
        }
        statusMessage = "当前已是最新版本"
    }

    fileprivate func handleUpdateCycleFinished(error: Error?) {
        lastCheckedAt = Date()
        isCheckingForUpdates = false

        if let error {
            let nsError = error as NSError
            if nsError.code != SUNoUpdateError {
                statusMessage = error.localizedDescription
            }
        }
    }

    fileprivate func handleAbort(error: Error) {
        isCheckingForUpdates = false
        statusMessage = error.localizedDescription
    }
#endif
}

#if canImport(Sparkle)
private final class SparkleUpdaterDelegateBridge: NSObject, SPUUpdaterDelegate {
    weak var owner: SparkleUpdater?

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        owner?.handleFoundUpdate(item)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        owner?.handleNoUpdateFound(error)
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        owner?.handleAbort(error: error)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        owner?.handleUpdateCycleFinished(error: error)
    }
}
#endif
