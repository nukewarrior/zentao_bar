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
    private var lastRotationDate: String?

    func write(_ message: String) {
        guard enabled else { return }

        do {
            try prepareIfNeeded()
            try rotateIfNeeded()
            try cleanupOldArchives()

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss,SSS"
            let timestamp = formatter.string(from: Date())
            let line = "[\(timestamp)] \(message)\n"
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

    // MARK: - Rotation

    private var todayString: String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: Date())
    }

    private func rotateIfNeeded() throws {
        guard let today = todayString else { return }

        if let last = lastRotationDate, last == today {
            return
        }

        lastRotationDate = today

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        let attrs = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        if let modDate = attrs[.modificationDate] as? Date {
            let modFormatter = DateFormatter()
            modFormatter.dateFormat = "yyyyMMdd"
            let modDay = modFormatter.string(from: modDate)
            if modDay == today {
                return
            }
        }

        let archiveName = "zentao_bar.\(formattedFileDate()).tar.gz"
        let archiveURL = directoryURL.appendingPathComponent(archiveName)

        let result = try tar(archiveURL: archiveURL)

        if result == 0 {
            try Data().write(to: fileURL, options: .atomic)
        }
    }

    private func formattedFileDate() -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: fileURL.path))
        let modDate = attrs?[.modificationDate] as? Date ?? Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: modDate)
    }

    // MARK: - Cleanup

    private func cleanupOldArchives() throws {
        let files = try FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: .skipsHiddenFiles
        )

        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()

        for file in files {
            let name = file.lastPathComponent
            guard name.hasPrefix("zentao_bar."), name.hasSuffix(".tar.gz") else { continue }

            let attrs = try file.resourceValues(forKeys: [.contentModificationDateKey])
            if let modDate = attrs.contentModificationDate, modDate < cutoff {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Helpers

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

    private func tar(archiveURL: URL) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = [
            "-czf", archiveURL.path,
            "-C", directoryURL.path,
            "zentao_bar.log"
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        try process.run()
        process.waitUntilExit()

        return process.terminationStatus
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
