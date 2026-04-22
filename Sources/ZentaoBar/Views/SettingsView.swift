import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var preferences: PreferencesStore

    @State private var baseURL = ""
    @State private var account = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            Group {
                switch preferences.selectedSettingsTab {
                case .account:
                    AccountSettingsView(
                        baseURL: $baseURL,
                        account: $account,
                        password: $password,
                        isSubmitting: $isSubmitting,
                        onSave: submitLogin,
                        onLogout: {
                            password = ""
                            appState.logout()
                            syncFormFromConfig(resetPassword: false)
                        },
                        onOpenZentao: { appState.openZentaoHome() }
                    )
                case .general:
                    GeneralSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
        }
        .frame(width: 820, height: 560)
        .onAppear {
            syncFormFromConfig(resetPassword: true)
        }
        .onChange(of: appState.config?.baseURL) { _, _ in
            syncFormFromConfig(resetPassword: false)
        }
        .onChange(of: appState.config?.account) { _, _ in
            syncFormFromConfig(resetPassword: false)
        }
    }

    private var header: some View {
        HStack {
            Spacer()

            HStack(spacing: 14) {
                tabButton(.account, systemImage: "person.crop.circle", title: "账户")
                tabButton(.general, systemImage: "slider.horizontal.3", title: "设置")
                tabButton(.about, systemImage: "info.circle", title: "关于")
            }

            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func tabButton(_ tab: SettingsTab, systemImage: String, title: String) -> some View {
        let isSelected = preferences.selectedSettingsTab == tab

        return Button {
            preferences.openSettings(tab: tab)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .medium))
                Text(title)
                    .font(.headline.weight(.medium))
            }
            .frame(width: 92, height: 72)
            .foregroundStyle(isSelected ? .blue : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? .blue.opacity(0.08) : .white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? .blue.opacity(0.35) : .white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func submitLogin() {
        Task {
            isSubmitting = true
            let succeeded = await appState.login(
                baseURL: baseURL,
                account: account,
                password: password
            )
            isSubmitting = false
            if succeeded {
                password = ""
            }
        }
    }

    private func syncFormFromConfig(resetPassword: Bool) {
        baseURL = appState.config?.baseURL ?? ""
        account = appState.config?.account ?? ""

        if resetPassword {
            password = ""
        }
    }
}
