import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private let metadata = AppMetadata.current

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(metadata.displayName)
                        .font(.title.weight(.semibold))
                    Text("禅道菜单栏工时工具")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Divider()

                infoRow("版本", metadata.version)
                infoRow("构建号", metadata.buildNumber)
                infoRow("构建配置", metadata.buildConfiguration)
                infoRow("Bundle ID", metadata.bundleIdentifier)
                infoRow("可执行文件", metadata.executableName)
                infoRow("调试日志", metadata.isDebugBuild ? "已启用" : "未启用")
                infoRow("日志路径", metadata.isDebugBuild ? DebugLogger.logFilePath : "release 构建不写日志")
                infoRow("刷新策略", "60 秒缓存窗口，非后台轮询")

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
                }
            }
            .padding(24)
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
        """

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    private func openLogDirectory() {
        let directory = (DebugLogger.logFilePath as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: directory))
    }
}
