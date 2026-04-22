import SwiftUI

struct AccountSettingsView: View {
    @EnvironmentObject private var appState: AppState

    @Binding var baseURL: String
    @Binding var account: String
    @Binding var password: String
    @Binding var isSubmitting: Bool

    let onSave: () -> Void
    let onLogout: () -> Void
    let onOpenZentao: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detailPanel
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            accountCard

            Spacer(minLength: 0)

            Button(sidebarButtonTitle) {
                onSave()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(isSubmitting)
        }
        .padding(16)
        .frame(width: 220, alignment: .topLeading)
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.08))
                    Text(accountInitial)
                        .font(.system(size: 24, weight: .semibold))
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 4) {
                    Text(accountDisplayName)
                        .font(.headline)
                        .lineLimit(1)
                    Text(baseURLDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(appState.isLoggedIn ? .green : .secondary)
                    .frame(width: 8, height: 8)
                Text(appState.isLoggedIn ? "已登录" : "未登录")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
    }

    private var detailPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.08))
                            Text(accountInitial)
                                .font(.system(size: 34, weight: .semibold))
                        }
                        .frame(width: 92, height: 92)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(accountDisplayName)
                                .font(.title2.weight(.semibold))
                            Text(baseURLDisplay)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    infoGrid

                    HStack(spacing: 10) {
                        Button(primaryActionTitle) {
                            onSave()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)

                        Button("退出登录") {
                            onLogout()
                        }
                        .buttonStyle(.bordered)
                        .disabled(!appState.isLoggedIn)

                        Button("打开禅道") {
                            onOpenZentao()
                        }
                        .buttonStyle(.bordered)
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 12) {
                    Text("账户信息")
                        .font(.headline)

                    Form {
                        TextField("禅道地址", text: $baseURL)
                            .textFieldStyle(.roundedBorder)

                        TextField("账号", text: $account)
                            .textFieldStyle(.roundedBorder)

                        SecureField("密码", text: $password)
                            .textFieldStyle(.roundedBorder)
                    }
                    .formStyle(.grouped)

                    if let errorMessage = appState.errorMessage {
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Spacer()

                        Button(primaryActionTitle) {
                            onSave()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(isSubmitting)
                    }
                }
            }
            .padding(20)
        }
    }

    private var infoGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            infoRow("账号", accountDisplayName)
            infoRow("禅道地址", baseURLDisplay)
            infoRow("状态", appState.isLoggedIn ? "已登录" : "未登录")
            infoRow("最近刷新", appState.lastUpdatedText.replacingOccurrences(of: "上次更新于 ", with: ""))
            infoRow("今日工时", appState.formattedTotalWithUnit)
            infoRow("当前任务", "\(appState.currentTaskCount)")
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(label)
                .font(.body.weight(.medium))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private var accountDisplayName: String {
        let trimmed = account.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return appState.config?.account ?? "未配置账户"
    }

    private var baseURLDisplay: String {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            return trimmed
        }
        return appState.config?.baseURL ?? "未配置禅道地址"
    }

    private var accountInitial: String {
        String(accountDisplayName.prefix(1)).uppercased()
    }

    private var sidebarButtonTitle: String {
        if isSubmitting {
            return "登录中..."
        }

        return appState.isLoggedIn ? "重新登录..." : "添加账户..."
    }

    private var primaryActionTitle: String {
        if isSubmitting {
            return "登录中..."
        }

        return appState.isLoggedIn ? "重新登录" : "登录并保存"
    }
}
