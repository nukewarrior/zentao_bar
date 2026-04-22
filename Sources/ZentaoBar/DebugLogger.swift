import Foundation

actor DebugLogWriter {
    static let shared = DebugLogWriter()

    private let enabled = AppMetadata.current.isDebugBuild
    private let directoryURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zentao_bar", isDirectory: true)
    private let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".zentao_bar", isDirectory: true)
        .appendingPathComponent("zentao_bar.log", isDirectory: false)
    private var prepared = false

    func write(_ message: String) {
        guard enabled else { return }

        do {
            try prepareIfNeeded()

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let line = "[\(formatter.string(from: Date()))] \(message)\n"
            let data = Data(line.utf8)

            if let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: fileURL, options: .atomic)
            }
        } catch {
            // Intentionally swallow logging failures to avoid affecting app behavior.
        }
    }

    private func prepareIfNeeded() throws {
        guard !prepared else { return }

        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }

        prepared = true
    }
}

enum DebugLogger {
    static var isEnabled: Bool {
        AppMetadata.current.isDebugBuild
    }

    static var logFilePath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".zentao_bar", isDirectory: true)
            .appendingPathComponent("zentao_bar.log", isDirectory: false)
            .path
    }

    static func log(_ message: String) {
        guard isEnabled else { return }
        Task {
            await DebugLogWriter.shared.write(message)
        }
    }

    static func logResponsePreview(path: String, data: Data) {
        guard isEnabled else { return }

        let preview: String
        if path == "/api.php/v1/tokens" {
            preview = "<omitted>"
        } else if let text = String(data: data, encoding: .utf8) {
            preview = String(text.prefix(800))
        } else {
            preview = "<non-utf8 \(data.count) bytes>"
        }

        log("Response preview for \(path): \(preview)")
    }
}
