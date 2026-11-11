import Foundation

public struct MCPServer: Sendable {
    // Newest first; an unknown requested version gets the newest.
    public static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    public var name: String
    public var version: String
    public var showFileFormat: @Sendable () -> String?
    public var check: @Sendable (String) async -> CheckReport
    public var openFiles: @Sendable () -> [URL]?
    // Returns where the file went, so a failed write can put it back.
    public var trash: @Sendable (URL) throws -> URL?
    public var log: @Sendable (String) -> Void

    public init(
        name: String,
        version: String,
        showFileFormat: @escaping @Sendable () -> String?,
        check: @escaping @Sendable (String) async -> CheckReport,
        openFiles: @escaping @Sendable () -> [URL]?,
        trash: @escaping @Sendable (URL) throws -> URL?,
        log: @escaping @Sendable (String) -> Void
    ) {
        self.name = name
        self.version = version
        self.showFileFormat = showFileFormat
        self.check = check
        self.openFiles = openFiles
        self.trash = trash
        self.log = log
    }

    var instructions: String {
        """
        \(name) plays movie and concert JSON files behind a live orchestra. Call show_file_format before writing a \
        show. Read an existing file with read_show before changing it, then send the whole file to write_show: \
        fields left out are lost. Paths are absolute or start with ~; inside a show they may also be relative to its \
        file. check_show reports problems and writes nothing.
        """
    }

    // nil for a notification or a blank line: neither gets a reply.
    public func handle(_ line: String) async -> String? {
        guard !line.allSatisfy(\.isWhitespace) else { return nil }
        guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8), options: .fragmentsAllowed)
        else { return reply(id: nil, error: -32700, "Parse error") }
        guard let request = message as? [String: Any] else { return reply(id: nil, error: -32600, "Invalid request") }
        guard request.keys.contains("id") else { return nil }
        let id = request["id"].flatMap { Self.isID($0) ? $0 : nil }
        guard let id, request["jsonrpc"] as? String == "2.0", let method = request["method"] as? String else {
            return reply(id: id, error: -32600, "Invalid request")
        }
        let params = request["params"] as? [String: Any] ?? [:]
        switch method {
        case "initialize":
            let requested = params["protocolVersion"] as? String ?? ""
            let result: [String: Any] = [
                "protocolVersion": Self.protocolVersions.contains(requested) ? requested : Self.protocolVersions[0],
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": name.lowercased(), "version": version],
                "instructions": instructions,
            ]
            return reply(id: id, result: result)
        case "ping":
            return reply(id: id, result: [String: Any]())
        case "tools/list":
            return reply(id: id, result: ["tools": tools])
        case "tools/call":
            let name = params["name"] as? String ?? ""
            guard let outcome = await call(name, params["arguments"]) else {
                return reply(id: id, error: -32602, "Unknown tool: \(name)")
            }
            return reply(
                id: id, result: ["content": [["type": "text", "text": outcome.text]], "isError": outcome.isError])
        default:
            return reply(id: id, error: -32601, "Method not found: \(method)")
        }
    }

    // JSON true and false also arrive as NSNumber.
    private static func isID(_ value: Any) -> Bool {
        if value is String { return true }
        guard let number = value as? NSNumber else { return false }
        return CFGetTypeID(number) != CFBooleanGetTypeID()
    }

    private func reply(id: Any?, result: Any) -> String {
        line(["jsonrpc": "2.0", "id": id ?? NSNull(), "result": result])
    }

    private func reply(id: Any?, error code: Int, _ message: String) -> String {
        line(["jsonrpc": "2.0", "id": id ?? NSNull(), "error": ["code": code, "message": message] as [String: Any]])
    }

    // Not pretty-printed: newlines inside strings are escaped, so a message is always one line.
    private func line(_ message: [String: Any]) -> String {
        let data = try? JSONSerialization.data(
            withJSONObject: message, options: [.sortedKeys, .withoutEscapingSlashes])
        return String(decoding: data ?? Data(), as: UTF8.self)
    }

    var tools: [[String: Any]] {
        let path: [String: Any] = ["type": "string", "description": "Absolute path, or one starting with ~."]
        let pathOnly: [String: Any] = ["type": "object", "properties": ["path": path], "required": ["path"]]
        return [
            [
                "name": "show_file_format",
                "description": """
                The \(name) show file format (movie and concert JSON) as Markdown. Read it before writing a show.
                """,
                "inputSchema": ["type": "object", "properties": [String: Any]()] as [String: Any],
            ],
            [
                "name": "read_show",
                "description": """
                Read a \(name) show: a .movie.json, a .concert.json or a clip folder. Returns JSON \
                {"path", "saved", "show"}, where show is the file as \(name) reads it. A clip folder returns its \
                <folder>.movie.json; without one, the movie \(name) would generate from the NN_name.mp4 files, \
                with saved false and path where it would be saved. Refused when \(name) cannot load the show. \
                Writes nothing.
                """,
                "inputSchema": pathOnly,
            ],
            [
                "name": "write_show",
                "description": """
                Write a complete \(name) movie or concert file and return its check report (as check_show). path \
                must end in .movie.json or .concert.json (the suffix sets the type) and its folder must exist. \
                show is the whole file as a JSON object: fields left out are lost, so read_show a file before \
                changing it. Paths inside the show that are absolute or start with ~ are stored relative when \
                they are inside the file's folder, else absolute. A file it replaces goes to the macOS Trash \
                first, and the result says so: tell the user. Refused, with nothing written: an invalid show \
                (format, item types, a clip in a concert, a movie in a movie, a movie file that is missing or \
                does not load), because \(name) could not open it; and a file open in a running \(name), because \
                the app's next save would overwrite it: ask the user to close the show in \(name), then retry.
                """,
                "inputSchema": [
                    "type": "object",
                    "properties": [
                        "path": path,
                        "show": ["type": "object", "description": "The complete movie or concert."] as [String: Any],
                    ],
                    "required": ["path", "show"],
                ] as [String: Any],
            ],
            [
                "name": "check_show",
                "description": """
                Check a \(name) show like `\(name) --check`: a .movie.json, a .concert.json or a clip folder. \
                Returns the JSON report: result ok, warnings (still plays), blocked (a clip cannot play) or \
                error (the show cannot be loaded), with findings per cue such as missing or unplayable clips \
                and timing mismatches. Writes nothing.
                """,
                "inputSchema": pathOnly,
            ],
        ]
    }
}
