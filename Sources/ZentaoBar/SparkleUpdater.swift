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
        log("start() requested")
        logEnvironmentSnapshot(context: "before-start")
        updaterController.startUpdater()
        logUpdaterState(context: "after-start")
        setStatusMessage("更新服务已启动")
        syncUpdaterPreferences()
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    func checkForUpdates(userInitiated: Bool) {
#if canImport(Sparkle)
        isCheckingForUpdates = true
        log("checkForUpdates(userInitiated: \(userInitiated))")
        logUpdaterState(context: "before-check")
        setStatusMessage(userInitiated ? "正在检查更新..." : "后台检查更新...")
        updaterController.checkForUpdates(nil)
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if canImport(Sparkle)
        updaterController.updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
        log("automaticallyChecksForUpdates set to \(enabled)")
        setStatusMessage(enabled ? "已开启自动检查更新" : "已关闭自动检查更新")
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    func setUpdateCheckInterval(_ option: UpdateCheckIntervalOption) {
#if canImport(Sparkle)
        updaterController.updater.updateCheckInterval = option.seconds
        updateCheckIntervalOption = option
        log("updateCheckInterval set to \(option.seconds)s (\(option.title))")
        setStatusMessage("检查间隔已更新为 \(option.title)")
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    private func configure() {
#if canImport(Sparkle)
        delegateBridge.owner = self
        log("configure()")
        logEnvironmentSnapshot(context: "configure")
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
                self?.log("canCheckForUpdates changed to \(value)")
            }
            .store(in: &cancellables)
        updaterController.updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.automaticallyChecksForUpdates = value
                self?.log("automaticallyChecksForUpdates changed to \(value)")
            }
            .store(in: &cancellables)
        updaterController.updater.publisher(for: \.updateCheckInterval)
            .map { UpdateCheckIntervalOption(seconds: $0) ?? .seconds120 }
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.updateCheckIntervalOption = value
                self?.log("updateCheckInterval changed to \(value.seconds)s (\(value.title))")
            }
            .store(in: &cancellables)
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

#if canImport(Sparkle)
    private func syncUpdaterPreferences() {
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates
        updateCheckIntervalOption = UpdateCheckIntervalOption(seconds: updaterController.updater.updateCheckInterval) ?? .seconds120
        logUpdaterState(context: "sync-preferences")
    }
#endif

#if canImport(Sparkle)
    fileprivate func handleFoundUpdate(_ item: SUAppcastItem) {
        latestAvailableVersion = item.displayVersionString
        log("didFindValidUpdate version=\(item.displayVersionString) build=\(item.versionString)")
        setStatusMessage("发现新版本 \(item.displayVersionString)")
    }

    fileprivate func handleNoUpdateFound(_ error: Error) {
        let nsError = error as NSError
        if let latestItem = nsError.userInfo[SPULatestAppcastItemFoundKey] as? SUAppcastItem {
            latestAvailableVersion = latestItem.displayVersionString
        }
        log("updaterDidNotFindUpdate error=\(describe(error: error))")
        setStatusMessage("当前已是最新版本")
    }

    fileprivate func handleUpdateCycleFinished(error: Error?) {
        lastCheckedAt = Date()
        isCheckingForUpdates = false

        if let error {
            let nsError = error as NSError
            log("didFinishUpdateCycle error=\(describe(error: error))")
            if !(nsError.domain == SUSparkleErrorDomain && nsError.code == 1001) {
                setStatusMessage(error.localizedDescription)
            }
        } else {
            log("didFinishUpdateCycle success")
        }

        logUpdaterState(context: "after-update-cycle")
    }

    fileprivate func handleAbort(error: Error) {
        isCheckingForUpdates = false
        log("didAbortWithError \(describe(error: error))")
        logEnvironmentSnapshot(context: "abort")
        setStatusMessage(error.localizedDescription)
    }
#endif

    private func setStatusMessage(_ message: String) {
        statusMessage = message
        log("statusMessage=\(message)")
    }

    private func log(_ message: String) {
        DebugLogger.log("[Sparkle] \(message)")
    }
}

#if canImport(Sparkle)
private extension SparkleUpdater {
    func logUpdaterState(context: String) {
        log(
            "\(context) state: canCheck=\(updaterController.updater.canCheckForUpdates), " +
            "autoChecks=\(updaterController.updater.automaticallyChecksForUpdates), " +
            "interval=\(Int(updaterController.updater.updateCheckInterval))s"
        )
    }

    func logEnvironmentSnapshot(context: String) {
        let bundle = Bundle.main
        let frameworkURL = bundle.privateFrameworksURL?.appendingPathComponent("Sparkle.framework", isDirectory: true)
        let frameworkPath = frameworkURL?.path ?? "<missing-frameworks-dir>"
        let autoupdatePath = frameworkURL?.appendingPathComponent("Autoupdate", isDirectory: false).path ?? "<missing>"
        let updaterAppPath = frameworkURL?.appendingPathComponent("Updater.app", isDirectory: true).path ?? "<missing>"
        let xpcServicesPath = frameworkURL?.appendingPathComponent("XPCServices", isDirectory: true).path ?? "<missing>"

        log(
            "\(context) environment: app=\(bundle.bundleURL.path), " +
            "version=\(AppMetadata.current.version) (\(AppMetadata.current.buildNumber)), " +
            "feedURL=\(updateFeedURL), publicKey=\(publicKeyStateDescription)"
        )
        log("\(context) frameworkPath=\(frameworkPath), exists=\(fileExists(at: frameworkPath))")
        log("\(context) autoupdatePath=\(autoupdatePath), exists=\(fileExists(at: autoupdatePath))")
        log("\(context) updaterAppPath=\(updaterAppPath), exists=\(fileExists(at: updaterAppPath))")
        log("\(context) xpcServicesPath=\(xpcServicesPath), exists=\(fileExists(at: xpcServicesPath))")
        log("\(context) frameworkContents=\(directoryListing(at: frameworkPath))")
        log("\(context) xpcServicesContents=\(directoryListing(at: xpcServicesPath))")
    }

    func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    func directoryListing(at path: String) -> String {
        guard FileManager.default.fileExists(atPath: path) else {
            return "<missing>"
        }

        do {
            let entries = try FileManager.default.contentsOfDirectory(atPath: path).sorted()
            return entries.isEmpty ? "<empty>" : entries.joined(separator: ", ")
        } catch {
            return "<unreadable: \(error.localizedDescription)>"
        }
    }

    func describe(error: Error) -> String {
        let nsError = error as NSError
        var components = [
            "domain=\(nsError.domain)",
            "code=\(nsError.code)",
            "description=\(nsError.localizedDescription)"
        ]

        if let failureReason = nsError.localizedFailureReason, !failureReason.isEmpty {
            components.append("reason=\(failureReason)")
        }

        if let recoverySuggestion = nsError.localizedRecoverySuggestion, !recoverySuggestion.isEmpty {
            components.append("suggestion=\(recoverySuggestion)")
        }

        let userInfoSummary = nsError.userInfo
            .map { key, value in
                "\(key)=\(summarizeUserInfoValue(value))"
            }
            .sorted()
            .joined(separator: ", ")

        if !userInfoSummary.isEmpty {
            components.append("userInfo=[\(userInfoSummary)]")
        }

        return components.joined(separator: "; ")
    }

    func summarizeUserInfoValue(_ value: Any) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let url as URL:
            return url.absoluteString
        case let item as SUAppcastItem:
            return "SUAppcastItem(version=\(item.displayVersionString), build=\(item.versionString))"
        case let error as NSError:
            return "NSError(domain=\(error.domain), code=\(error.code), description=\(error.localizedDescription))"
        default:
            return String(describing: type(of: value))
        }
    }
}

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
