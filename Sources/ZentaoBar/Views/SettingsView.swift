import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var baseURL = ""
    @State private var account = ""
    @State private var password = ""
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("禅道设置")
                .font(.title2.weight(.semibold))

            Text("请输入禅道地址、账号和密码。地址只需要填写站点根地址，例如 `http://host:port/zentao`。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

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
                Button("退出登录") {
                    appState.logout()
                }
                .disabled(appState.config == nil)

                Spacer()

                Button("取消") {
                    dismiss()
                }

                Button(isSubmitting ? "登录中..." : "登录并保存") {
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
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isSubmitting)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            baseURL = appState.config?.baseURL ?? ""
            account = appState.config?.account ?? ""
            password = ""
        }
    }
}

