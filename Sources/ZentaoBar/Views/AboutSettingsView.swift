import AppKit
import SwiftUI

struct AboutSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var updateReminder: UpdateReminderService

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
                        infoRow("版本源", updateReminder.releasesMetadataURLDescription)
                        infoRow("发布仓库", updateReminder.repositoryURLDescription)
                        infoRow("自动检查", preferences.updateChecksEnabled ? "已开启" : "已关闭")
                        infoRow("检查间隔", preferences.updateCheckInterval.title)
                        infoRow("最新版本", updateReminder.latestVersionDescription)
                        infoRow("发布时间", updateReminder.latestPublishedText)
                        infoRow("上次检查", updateReminder.lastCheckedText)

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

                            Button("立即检查新版本") {
                                updateReminder.checkForUpdates(userInitiated: true)
                            }
                            .buttonStyle(.bordered)
                            .disabled(updateReminder.isCheckingForUpdates)

                            Button("前往下载最新版") {
                                updateReminder.openLatestReleasePage()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!updateReminder.canOpenLatestReleasePage)
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
        Release Metadata: \(updateReminder.releasesMetadataURLDescription)
        Repository: \(updateReminder.repositoryURLDescription)
        Auto Checks: \(preferences.updateChecksEnabled ? "Enabled" : "Disabled")
        Latest Version: \(updateReminder.latestVersionDescription)
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
