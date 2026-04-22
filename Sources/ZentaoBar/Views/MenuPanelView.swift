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
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天工时：\(appState.formattedTotalWithUnit)")
                        .font(.system(size: 18, weight: .semibold))
                    Text(appState.lastUpdatedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button {
                    Task {
                        await appState.refresh(force: true)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("刷新")
            }
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
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(.white.opacity(0.08))

            HStack(spacing: 18) {
                footerIconButton(systemImage: "gearshape.fill", title: "设置") {
                    openSettingsWindow()
                }

                footerIconButton(systemImage: "globe", title: "打开禅道") {
                    appState.openZentaoHome()
                }

                footerIconButton(systemImage: "info.circle.fill", title: "关于") {
                    openAboutWindow()
                }

                footerIconButton(systemImage: "power", title: "退出") {
                    appState.quitApplication()
                }

                Spacer(minLength: 0)
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

            HStack(spacing: 18) {
                footerIconButton(systemImage: "person.crop.circle.badge.exclamationmark", title: "登录") {
                    openSettingsWindow()
                }

                footerIconButton(systemImage: "gearshape.fill", title: "设置") {
                    openSettingsWindow()
                }

                footerIconButton(systemImage: "info.circle.fill", title: "关于") {
                    openAboutWindow()
                }

                footerIconButton(systemImage: "power", title: "退出") {
                    appState.quitApplication()
                }

                Spacer(minLength: 0)
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

    private func footerIconButton(systemImage: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 18, height: 18)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .help(title)
    }

    private var isFailedState: Bool {
        if case .failed = appState.loadState {
            return true
        }

        return false
    }
}
