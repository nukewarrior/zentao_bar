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
        .frame(width: 860, height: 620)
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
        VStack(spacing: 16) {
            Text("ZentaoBar Settings")
                .font(.title2.weight(.semibold))

            HStack(spacing: 24) {
                tabButton(.account, systemImage: "person.crop.circle", title: "账户")
                tabButton(.general, systemImage: "slider.horizontal.3", title: "设置")
                tabButton(.about, systemImage: "info.circle", title: "关于")
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private func tabButton(_ tab: SettingsTab, systemImage: String, title: String) -> some View {
        let isSelected = preferences.selectedSettingsTab == tab

        return Button {
            preferences.openSettings(tab: tab)
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 24, weight: .medium))
                Text(title)
                    .font(.headline)
            }
            .frame(width: 108, height: 84)
            .foregroundStyle(isSelected ? .blue : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? .blue.opacity(0.08) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? .blue.opacity(0.35) : .clear, lineWidth: 1)
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
