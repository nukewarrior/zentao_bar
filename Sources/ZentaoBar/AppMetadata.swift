import Foundation

struct AppMetadata {
    let displayName: String
    let version: String
    let buildNumber: String
    let buildConfiguration: String
    let bundleIdentifier: String
    let executableName: String

    static let current = AppMetadata(bundle: .main)

    init(bundle: Bundle) {
        displayName =
            bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ??
            "ZentaoBar"
        version =
            bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ??
            "开发版本"
        buildNumber =
            bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ??
            "-"
        buildConfiguration =
            bundle.object(forInfoDictionaryKey: "ZentaoBuildConfiguration") as? String ??
            "debug"
        bundleIdentifier = bundle.bundleIdentifier ?? "com.codex.zentaobar"
        executableName =
            bundle.object(forInfoDictionaryKey: "ZentaoExecutableName") as? String ??
            bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String ??
            "ZentaoBar"
    }
}

