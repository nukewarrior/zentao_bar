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
    @Published private(set) var updaterSessionInProgress = false
    @Published private(set) var updateCheckIntervalOption: UpdateCheckIntervalOption = .seconds120
    @Published private(set) var latestAvailableVersion: String?
    @Published private(set) var lastCheckedAt: Date?
    @Published private(set) var statusMessage: String? = "尚未检查"

#if canImport(Sparkle)
    private let delegateBridge = SparkleUpdaterDelegateBridge()
    private let userDriver: SPUStandardUserDriver
    private let updater: SPUUpdater
#endif
    private var cancellables = Set<AnyCancellable>()

    init() {
#if canImport(Sparkle)
        userDriver = SPUStandardUserDriver(
            hostBundle: .main,
            delegate: nil
        )
        updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: delegateBridge
        )
#endif
        configure()
    }

    var updateFeedURL: String {
        Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String ?? "未配置"
    }

    var publicKeyStateDescription: String {
        guard hasConfiguredPublicKey else {
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
        guard validateConfiguration(context: "start") else {
            return
        }
        runDiagnosticsIfNeeded(context: "start")
        do {
            try updater.start()
            logUpdaterState(context: "after-start")
            setStatusMessage("更新服务已启动")
            syncUpdaterPreferences()
            scheduleDelayedStateSnapshots()
        } catch {
            log("start failed: \(describe(error: error))")
            setStatusMessage(error.localizedDescription)
        }
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    func checkForUpdates(userInitiated: Bool) {
#if canImport(Sparkle)
        guard validateConfiguration(context: "check") else {
            isCheckingForUpdates = false
            return
        }
        isCheckingForUpdates = true
        log("checkForUpdates(userInitiated: \(userInitiated))")
        logUpdaterState(context: "before-check")
        setStatusMessage(userInitiated ? "正在检查更新..." : "后台检查更新...")
        updater.checkForUpdates()
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
#if canImport(Sparkle)
        updater.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = enabled
        log("automaticallyChecksForUpdates set to \(enabled)")
        setStatusMessage(enabled ? "已开启自动检查更新" : "已关闭自动检查更新")
#else
        setStatusMessage("当前构建未集成 Sparkle")
#endif
    }

    func setUpdateCheckInterval(_ option: UpdateCheckIntervalOption) {
#if canImport(Sparkle)
        updater.updateCheckInterval = option.seconds
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
        updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
                self?.log("canCheckForUpdates changed to \(value)")
            }
            .store(in: &cancellables)
        updater.publisher(for: \.automaticallyChecksForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.automaticallyChecksForUpdates = value
                self?.log("automaticallyChecksForUpdates changed to \(value)")
            }
            .store(in: &cancellables)
        updater.publisher(for: \.sessionInProgress)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                self?.updaterSessionInProgress = value
                self?.log("sessionInProgress changed to \(value)")
            }
            .store(in: &cancellables)
        updater.publisher(for: \.updateCheckInterval)
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
        automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        updateCheckIntervalOption = UpdateCheckIntervalOption(seconds: updater.updateCheckInterval) ?? .seconds120
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

private enum SparkleRuntimeDiagnostics {
    static func logCodeSigningDiagnostics(context: String) {
        let bundle = Bundle.main
        let appPath = bundle.bundleURL.path
        let frameworkPath = bundle.privateFrameworksURL?
            .appendingPathComponent("Sparkle.framework", isDirectory: true)
            .path
        let autoupdatePath = frameworkPath.map { ($0 as NSString).appendingPathComponent("Autoupdate") }
        let updaterAppPath = frameworkPath.map { ($0 as NSString).appendingPathComponent("Updater.app") }
        let downloaderXPCPath = frameworkPath.map { ($0 as NSString).appendingPathComponent("XPCServices/Downloader.xpc") }
        let installerXPCPath = frameworkPath.map { ($0 as NSString).appendingPathComponent("XPCServices/Installer.xpc") }

        [
            ("app", Optional(appPath)),
            ("framework", frameworkPath),
            ("autoupdate", autoupdatePath),
            ("updaterApp", updaterAppPath),
            ("downloaderXPC", downloaderXPCPath),
            ("installerXPC", installerXPCPath)
        ]
        .forEach { label, path in
            guard let path else {
                DebugLogger.log("[Sparkle] \(context) codesign \(label): <missing path>")
                return
            }

            let verification = runCodesign(arguments: ["--verify", "--deep", "--strict", "--verbose=2", path])
            DebugLogger.log("[Sparkle] \(context) codesign \(label) verify exit=\(verification.status) output=\(verification.output)")

            let display = runCodesign(arguments: ["-dvv", path])
            DebugLogger.log("[Sparkle] \(context) codesign \(label) display exit=\(display.status) output=\(display.output)")
        }
    }

    static func runCodesign(arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let outputPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let rawOutput = String(data: data, encoding: .utf8) ?? "<non-utf8 output>"
            let normalizedOutput = rawOutput
                .replacingOccurrences(of: "\n", with: " | ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (process.terminationStatus, normalizedOutput.isEmpty ? "<empty>" : normalizedOutput)
        } catch {
            return (-1, "failed to run codesign: \(error.localizedDescription)")
        }
    }
}

#if canImport(Sparkle)
private extension SparkleUpdater {
    var hasConfiguredPublicKey: Bool {
        guard let rawKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }

        return !rawKey.isEmpty && rawKey != "SPARKLE_PUBLIC_ED_KEY_PLACEHOLDER"
    }

    var hasConfiguredFeedURL: Bool {
        guard let rawURL = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String else {
            return false
        }

        return !rawURL.isEmpty
    }

    func validateConfiguration(context: String) -> Bool {
        guard hasConfiguredFeedURL else {
            log("\(context) configuration invalid: missing SUFeedURL")
            setStatusMessage("更新地址未配置，当前构建无法检查更新")
            return false
        }

        guard hasConfiguredPublicKey else {
            log("\(context) configuration invalid: missing SUPublicEDKey")
            setStatusMessage("更新公钥未配置，当前构建无法检查更新")
            return false
        }

        return true
    }

    func logUpdaterState(context: String) {
        log(
            "\(context) state: canCheck=\(updater.canCheckForUpdates), " +
            "sessionInProgress=\(updater.sessionInProgress), " +
            "autoChecks=\(updater.automaticallyChecksForUpdates), " +
            "interval=\(Int(updater.updateCheckInterval))s"
        )
    }

    func scheduleDelayedStateSnapshots() {
        guard DebugLogger.isEnabled else {
            return
        }

        for delay in [1, 5, 15] {
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.logUpdaterState(context: "after-start+\(delay)s")
            }
        }
    }

    func runDiagnosticsIfNeeded(context: String) {
        guard DebugLogger.isEnabled else {
            return
        }

        Task.detached(priority: .utility) {
            SparkleRuntimeDiagnostics.logCodeSigningDiagnostics(context: context)
        }
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
