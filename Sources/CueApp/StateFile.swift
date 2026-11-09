import CueCore
import Foundation

enum StateFile {
    private static let queue = DispatchQueue(label: "state")
    // Only touched on the queue; keeps a failing disk from filling the log every second.
    private static var failing = false
    static let url = AppInfo.supportDirectory.appendingPathComponent("state.json")

    static func load() -> RecoveryState? {
        Recovery.load(from: url)
    }

    // Off the main thread, so a state write never delays the next key.
    static func save(_ state: RecoveryState) {
        queue.async { write(state) }
    }

    static func saveNow(_ state: RecoveryState) {
        queue.sync { write(state) }
    }

    // A folder opens as its generated movie file, so relaunching with the same folder still recovers.
    static func showPath(for argument: String) -> String {
        let url = URL(fileURLWithPath: argument).standardizedFileURL
        let movie = ShowLoader.movieFile(inFolder: url)
        return FileManager.default.fileExists(atPath: movie.path) ? movie.path : url.path
    }

    private static func write(_ state: RecoveryState) {
        do {
            try Recovery.save(state, to: url)
            failing = false
        } catch {
            if !failing { Log.info("state: cannot write \(url.path): \(error.localizedDescription)") }
            failing = true
        }
    }
}
