import AppKit
import CueCore

enum MCP {
    static func run() async -> Int32 {
        Log.headless = true
        // A client that goes away must not kill the process mid-write; the writes below ignore the error.
        signal(SIGPIPE, SIG_IGN)
        let server = MCPServer(
            name: AppInfo.name,
            version: AppInfo.version ?? "dev",
            showFileFormat: {
                Bundle.main.url(forResource: "show-files", withExtension: "md")
                    .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
            },
            check: { await Check.report(for: $0) },
            openFiles: { openFiles() },
            trash: { url in
                var trashed: NSURL?
                try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
                return trashed as URL?
            },
            log: { Log.info($0) })
        while let line = readLine() {
            guard let reply = await server.handle(line) else { continue }
            try? FileHandle.standardOutput.write(contentsOf: Data((reply + "\n").utf8))
        }
        Log.flush()
        return 0
    }

    // A state file naming a show while no app runs is left over from a quit or crash: nothing is open.
    private static func openFiles() -> [URL]? {
        // A bare build binary has no bundle ID, so it can find neither the running app nor its state file.
        guard let id = Bundle.main.bundleIdentifier else { return nil }
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != getpid() }
        guard !others.isEmpty else { return [] }
        return MCPServer.openFiles(showPath: StateFile.load()?.showPath)
    }
}
