import AppKit
import SwiftUI

struct MenuPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch appState.loadState {
            case .authRequired:
                authRequiredContent
            case .failed(let message):
                header
                errorBanner(message)
                footer
            case .empty:
                header
                emptyContent
                footer
            case .loading:
                header
                loadingContent
                if !appState.taskWorks.isEmpty {
                    taskList
                }
                footer
            case .loaded:
                header
                taskList
                footer
            case .idle:
                header
                loadingContent
                footer
            }
        }
        .padding(16)
        .frame(width: 320)
        .task {
            if appState.loadState == .idle {
                await appState.bootstrap()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今天工时：\(appState.formattedTotalWithUnit)")
                .font(.system(size: 18, weight: .semibold))
            Text(appState.lastUpdatedText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var taskList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(appState.taskWorks) { task in
                    Button {
                        appState.openTask(task)
                    } label: {
                        HStack(spacing: 12) {
                            Text(task.name)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(task.formattedConsumedWithUnit)
                                .foregroundStyle(.blue)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .help(task.name)

                    if task.id != appState.taskWorks.last?.id {
                        Divider()
                    }
                }
            }
        }
        .frame(maxHeight: 220)
        .background(Color.clear)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()

            Button("刷新") {
                Task {
                    await appState.refresh(force: true)
                }
            }

            Button("设置...") {
                openSettingsWindow()
            }

            Button("打开禅道") {
                appState.openZentaoHome()
            }

            Button("关于...") {
                openAboutWindow()
            }

            Button("退出") {
                appState.quitApplication()
            }

            if let errorMessage = appState.errorMessage,
               appState.loadState != .authRequired {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var authRequiredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("登录已失效，请重新登录")
                .font(.headline)

            Text(appState.errorMessage ?? "请先配置禅道地址、账号和密码。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            Button("登录...") {
                openSettingsWindow()
            }

            Button("设置...") {
                openSettingsWindow()
            }

            Button("关于...") {
                openAboutWindow()
            }

            Button("退出") {
                appState.quitApplication()
            }
        }
    }

    private var emptyContent: some View {
        Text("当前没有分配给你的任务")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }

    private var loadingContent: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text("正在刷新...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    private func errorBanner(_ message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 8)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func openAboutWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "about")
    }
}
