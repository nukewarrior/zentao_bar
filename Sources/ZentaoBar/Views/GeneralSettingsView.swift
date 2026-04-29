import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: PreferencesStore
    @EnvironmentObject private var updateReminder: UpdateReminderService

    var body: some View {
        ScrollView {
            VStack {
                VStack(alignment: .leading, spacing: 14) {
                    section("刷新与缓存") {
                        Toggle(
                            "自动后台刷新",
                            isOn: Binding(
                                get: { preferences.autoRefreshEnabled },
                                set: { preferences.setAutoRefreshEnabled($0) }
                            )
                        )

                        intervalPickerRow
                            .disabled(!preferences.autoRefreshEnabled)
                            .opacity(preferences.autoRefreshEnabled ? 1 : 0.5)

                        detailText("开启后应用会在后台按该间隔自动刷新；同一间隔也作为缓存有效期。手动点击刷新仍然会立即请求最新数据。")
                    }

                    section("更新") {
                        Toggle(
                            "自动检查新版本",
                            isOn: Binding(
                                get: { preferences.updateChecksEnabled },
                                set: { preferences.setUpdateChecksEnabled($0) }
                            )
                        )

                        updateIntervalPickerRow
                            .disabled(!preferences.updateChecksEnabled)
                            .opacity(preferences.updateChecksEnabled ? 1 : 0.5)

                        settingRow("版本源", value: updateReminder.releasesMetadataURLDescription)
                        settingRow("当前版本", value: AppMetadata.current.version)
                        settingRow("最新版本", value: updateReminder.latestVersionDescription)
                        settingRow("发布时间", value: updateReminder.latestPublishedText)
                        settingRow("上次检查", value: updateReminder.lastCheckedText)
                        settingRow("发布页", value: updateReminder.latestReleasePageDescription)

                        if let statusMessage = updateReminder.statusMessage {
                            detailText(statusMessage)
                        }

                        HStack(spacing: 10) {
                            Button("立即检查新版本") {
                                updateReminder.checkForUpdates(userInitiated: true)
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(updateReminder.isCheckingForUpdates)

                            Button("前往下载最新版") {
                                updateReminder.openLatestReleasePage()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!updateReminder.canOpenLatestReleasePage)

                            if updateReminder.isCheckingForUpdates {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }

                    section("窗口与显示") {
                        Toggle(
                            "点击任务后自动关闭面板",
                            isOn: Binding(
                                get: { preferences.autoCloseAfterTaskClick },
                                set: { preferences.setAutoCloseAfterTaskClick($0) }
                            )
                        )
                        Toggle(
                            "点击操作按钮后自动关闭面板",
                            isOn: Binding(
                                get: { preferences.autoCloseAfterActionClick },
                                set: { preferences.setAutoCloseAfterActionClick($0) }
                            )
                        )
                        settingRow("构建配置", value: AppMetadata.current.buildConfiguration)
                        settingRow("应用名称", value: AppMetadata.current.displayName)
                    }

                    section("调试") {
                        settingRow("日志文件", value: DebugLogger.logFilePath)

                        HStack(spacing: 10) {
                            Button("打开日志目录") {
                                openLogDirectory()
                            }
                            .buttonStyle(.bordered)

                            Button("复制日志路径") {
                                copyLogPath()
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(!AppMetadata.current.isDebugBuild)
                        .opacity(AppMetadata.current.isDebugBuild ? 1 : 0.5)

                        if !AppMetadata.current.isDebugBuild {
                            detailText("当前为 release 构建，不会写入调试日志。")
                        }
                    }

                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(18)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .background(cardBackground)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingRow(_ title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .font(.body.weight(.medium))
                .frame(width: 88, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var intervalPickerRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("刷新间隔")
                .font(.body.weight(.medium))
                .frame(width: 88, alignment: .leading)

            Picker("刷新间隔", selection: Binding(
                get: { preferences.autoRefreshInterval },
                set: { preferences.setAutoRefreshInterval($0) }
            )) {
                ForEach(RefreshIntervalOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var updateIntervalPickerRow: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("检查间隔")
                .font(.body.weight(.medium))
                .frame(width: 88, alignment: .leading)

            Picker("检查间隔", selection: Binding(
                get: { preferences.updateCheckInterval },
                set: { preferences.setUpdateCheckInterval($0) }
            )) {
                ForEach(UpdateCheckIntervalOption.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 104)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.white.opacity(0.08), lineWidth: 1)
            )
    }

    private func openLogDirectory() {
        let directory = (DebugLogger.logFilePath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
    }

    private func copyLogPath() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(DebugLogger.logFilePath, forType: .string)
    }
}
