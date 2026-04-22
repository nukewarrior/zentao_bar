import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: PreferencesStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                section("刷新与缓存") {
                    settingRow("缓存窗口", value: "60 秒")
                    detailText("当前行为是缓存窗口，不是后台自动轮询。60 秒内再次触发非强制刷新会优先复用已有数据。")
                    settingRow("自动刷新", value: "关闭（暂未启用后台轮询）")
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

                section("数据来源说明") {
                    settingRow("任务来源", value: "/tasks?assignedTo=me")
                    detailText("优先使用新版 API 获取分配给当前账号的任务。")
                    settingRow("回退一", value: "legacy my-work")
                    detailText("新版任务接口无权限时，回退到旧版“我的任务”入口。")
                    settingRow("回退二", value: "executions / projects")
                    detailText("旧入口仍不可用时，再回退到执行和项目遍历策略。")
                    settingRow("当前任务数", value: "\(appState.currentTaskCount)")
                }
            }
            .padding(24)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
            content()
        }
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

    private func detailText(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, 104)
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
