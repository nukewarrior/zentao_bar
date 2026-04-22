import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sparkleUpdater: SparkleUpdater

    private let metadata = AppMetadata.current

    var body: some View {
        ScrollView {
            VStack {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(metadata.displayName)
                            .font(.title2.weight(.semibold))
                        Text("禅道菜单栏工时工具")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .background(cardBackground)

                    VStack(alignment: .leading, spacing: 12) {
                        infoRow("版本", metadata.version)
                        infoRow("构建号", metadata.buildNumber)
                        infoRow("构建配置", metadata.buildConfiguration)
                        infoRow("Bundle ID", metadata.bundleIdentifier)
                        infoRow("可执行文件", metadata.executableName)
                        infoRow("调试日志", metadata.isDebugBuild ? "已启用" : "未启用")
                        infoRow("日志路径", metadata.isDebugBuild ? DebugLogger.logFilePath : "release 构建不写日志")
                        infoRow("刷新策略", appState.refreshPolicyDescription)
                        infoRow("更新源", sparkleUpdater.updateFeedDescription)
                        infoRow("自动检查更新", sparkleUpdater.automaticallyChecksForUpdates ? "已开启" : "已关闭")
                        infoRow("检查间隔", sparkleUpdater.updateIntervalDescription)
                        infoRow("最新版本", sparkleUpdater.latestVersionDescription)
                        infoRow("上次检查", sparkleUpdater.lastCheckedText)

                        HStack(spacing: 10) {
                            Button("复制版本信息") {
                                copyVersionInfo()
                            }
                            .buttonStyle(.bordered)

                            Button("打开日志目录") {
                                openLogDirectory()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!metadata.isDebugBuild)

                            Button("立即检查更新") {
                                sparkleUpdater.checkForUpdates(userInitiated: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(sparkleUpdater.isCheckingForUpdates || !sparkleUpdater.canCheckForUpdates)
                        }
                    }
                    .padding(16)
                    .background(cardBackground)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(18)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.body.weight(.medium))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func copyVersionInfo() {
        let value = """
        App: \(metadata.displayName)
        Version: \(metadata.version)
        Build: \(metadata.buildNumber)
        Configuration: \(metadata.buildConfiguration)
        Bundle ID: \(metadata.bundleIdentifier)
        Executable: \(metadata.executableName)
        Update Feed: \(sparkleUpdater.updateFeedDescription)
        Auto Checks: \(sparkleUpdater.automaticallyChecksForUpdates ? "Enabled" : "Disabled")
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openLogDirectory() {
        let directory = (DebugLogger.logFilePath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }
}
