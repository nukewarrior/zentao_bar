import SwiftUI

struct AboutView: View {
    private let metadata = AppMetadata.current

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(metadata.displayName)
                    .font(.title2.weight(.semibold))
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

            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 420, height: 240)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.body.weight(.medium))
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.body.monospaced())
                .textSelection(.enabled)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }
}
