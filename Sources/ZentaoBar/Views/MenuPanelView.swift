import AppKit
import SwiftUI

struct MenuPanelView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch appState.loadState {
            case .authRequired:
                authRequiredContent
            case .failed, .empty, .loading, .loaded, .idle:
                header
                statusBanner
                taskSection
                footer
                footerErrorMessage
            }
        }
        .padding(14)
        .frame(width: 320)
        .task {
            if appState.loadState == .idle {
                await appState.bootstrap()
            }
        }
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch appState.loadState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在刷新...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        case .failed(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        case .idle:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在刷新...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 2)
        default:
            EmptyView()
        }
    }

    private var taskSection: some View {
        Group {
            if appState.taskWorks.isEmpty {
                emptyTaskState
            } else {
                taskList
            }
        }
        .frame(height: 210)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
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
                        HStack(spacing: 8) {
                            Text(task.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(task.formattedConsumedWithUnit)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.blue)
                                .frame(width: 42, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                        .padding(.vertical, 7)
                    }
                    .buttonStyle(.plain)
                    .help(task.name)

                    if task.id != appState.taskWorks.last?.id {
                        Divider()
                            .overlay(.white.opacity(0.08))
                    }
                }
            }
        }
        .scrollIndicators(.visible)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .overlay(.white.opacity(0.08))

            HStack(spacing: 8) {
                Button("刷新") {
                    Task {
                        await appState.refresh(force: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Button("设置") {
                    openSettingsWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                Button("打开禅道") {
                    appState.openZentaoHome()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Menu {
                    Button("关于...") {
                        openAboutWindow()
                    }

                    Divider()

                    Button("退出") {
                        appState.quitApplication()
                    }
                } label: {
                    HStack {
                        Text("更多")
                        Spacer(minLength: 4)
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .menuStyle(.borderlessButton)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 1)
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var footerErrorMessage: some View {
        if let errorMessage = appState.errorMessage,
           appState.loadState != .authRequired,
           !isFailedState {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var authRequiredContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("登录已失效，请重新登录")
                .font(.headline)

            Text(appState.errorMessage ?? "请先配置禅道地址、账号和密码。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(.white.opacity(0.08))

            HStack(spacing: 8) {
                Button("登录") {
                    openSettingsWindow()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Button("设置") {
                    openSettingsWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                Button("关于") {
                    openAboutWindow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)

                Button("退出") {
                    appState.quitApplication()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private var emptyTaskState: some View {
        switch appState.loadState {
        case .empty:
            emptyContent
        case .loading, .idle:
            loadingContent
        case .failed:
            failedTaskPlaceholder
        default:
            emptyContent
        }
    }

    private var emptyContent: some View {
        Text("当前没有分配给你的任务")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var failedTaskPlaceholder: some View {
        Text("任务列表加载失败")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private var loadingContent: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("正在刷新...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
    }

    private func openAboutWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "about")
    }

    private var isFailedState: Bool {
        if case .failed = appState.loadState {
            return true
        }

        return false
    }
}
