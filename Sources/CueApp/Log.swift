import Foundation

enum Log {
    private static let keepDays: Double = 14
    private static let queue = DispatchQueue(label: "log")
    static let directory = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs", isDirectory: true)
        .appendingPathComponent(AppInfo.name, isDirectory: true)
    private static let stamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()
    private static let day: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        return formatter
    }()

    // Synchronous so a crash still leaves the last lines on disk.
    static func info(_ message: String) {
        let now = Date()
        queue.sync { write(message, at: now) }
    }

    // For the key-to-switch path, where a file write must not delay the next command.
    static func deferred(_ message: String) {
        let now = Date()
        queue.async { write(message, at: now) }
    }

    static var todayFile: URL {
        directory.appendingPathComponent(day.string(from: Date()) + ".log")
    }

    static func flush() {
        queue.sync {}
    }

    static func pruneOldFiles() {
        queue.async {
            let cutoff = Date().addingTimeInterval(-keepDays * 24 * 3600)
            let files =
                (try? FileManager.default.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.pathExtension == "log" {
                let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                if let modified, modified < cutoff { try? FileManager.default.removeItem(at: file) }
            }
        }
    }

    private static func write(_ message: String, at date: Date) {
        let line = "\(stamp.string(from: date)) \(message)"
        print(line)
        let data = Data((line + "\n").utf8)
        let file = directory.appendingPathComponent(day.string(from: date) + ".log")
        do {
            if !FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                FileManager.default.createFile(atPath: file.path, contents: nil)
            }
            let handle = try FileHandle(forWritingTo: file)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            print("log: cannot write \(file.path): \(error.localizedDescription)")
        }
    }
}
