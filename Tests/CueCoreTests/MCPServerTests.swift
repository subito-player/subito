import Foundation
import Testing

@testable import CueCore

// Stands in for the macOS Trash, so tests never touch the real one.
private let moveAside: @Sendable (URL) throws -> URL? = { url in
    let target = URL(fileURLWithPath: url.path + ".trashed")
    try FileManager.default.moveItem(at: url, to: target)
    return target
}

private func server(
    open: [URL]? = [], format: String? = "# Show files", trash: @escaping @Sendable (URL) throws -> URL? = moveAside
) -> MCPServer {
    MCPServer(
        name: "Player",
        version: "9.8.7",
        showFileFormat: { format },
        check: { path in CheckReport(show: path, title: "stub", cues: [], findings: []) },
        openFiles: { open },
        trash: trash,
        log: { _ in })
}

private func request(_ method: String, id: Any = 1, params: [String: Any]? = nil) throws -> String {
    var message: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
    if let params { message["params"] = params }
    return String(decoding: try JSONSerialization.data(withJSONObject: message), as: UTF8.self)
}

private func response(_ server: MCPServer, _ line: String) async throws -> [String: Any] {
    let reply = try #require(await server.handle(line))
    #expect(!reply.contains("\n"))
    return try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
}

private func call(_ server: MCPServer, _ tool: String, _ arguments: [String: Any]) async throws -> (
    text: String, isError: Bool
) {
    let reply = try await response(server, request("tools/call", params: ["name": tool, "arguments": arguments]))
    let result = try #require(reply["result"] as? [String: Any])
    let content = try #require(result["content"] as? [[String: Any]])
    #expect(content.count == 1 && content.first?["type"] as? String == "text")
    return (try #require(content.first?["text"] as? String), try #require(result["isError"] as? Bool))
}

private func errorCode(_ reply: [String: Any]) -> Int? {
    (reply["error"] as? [String: Any])?["code"] as? Int
}

@Suite struct MCPProtocolTests {
    @Test(arguments: MCPServer.protocolVersions)
    func initializeEchoesASupportedVersion(version: String) async throws {
        let reply = try await response(server(), request("initialize", params: ["protocolVersion": version]))
        #expect((reply["result"] as? [String: Any])?["protocolVersion"] as? String == version)
    }

    @Test func initializeOffersTheNewestForAnUnknownVersion() async throws {
        for params: [String: Any] in [["protocolVersion": "2099-01-01"], [:]] {
            let reply = try await response(server(), request("initialize", params: params))
            let result = try #require(reply["result"] as? [String: Any])
            #expect(result["protocolVersion"] as? String == "2025-11-25")
            #expect(result["serverInfo"] as? [String: String] == ["name": "player", "version": "9.8.7"])
            #expect((result["capabilities"] as? [String: Any])?["tools"] is [String: Any])
        }
    }

    @Test func notificationsGetNoReply() async {
        for line in [
            #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
            #"{"jsonrpc":"2.0","method":"notifications/cancelled","params":{"requestId":1}}"#,
            #"{"jsonrpc":"2.0","method":"no/such/method"}"#,
        ] {
            #expect(await server().handle(line) == nil)
        }
    }

    @Test(arguments: [
        ("{ not json", -32700),
        (#"[{"jsonrpc":"2.0","id":1,"method":"ping"}]"#, -32600),
        ("42", -32600),
        (#"{"jsonrpc":"2.0","id":true,"method":"ping"}"#, -32600),
    ])
    func unreadableLinesAndInvalidIDsGetAnErrorWithoutID(line: String, code: Int) async throws {
        let reply = try await response(server(), line)
        #expect(errorCode(reply) == code)
        #expect(reply["id"] is NSNull)
    }

    @Test func unknownMethodsAndMalformedRequestsKeepTheirID() async throws {
        let unknown = try await response(server(), request("resources/list", id: 7))
        #expect(errorCode(unknown) == -32601)
        #expect(unknown["id"] as? Int == 7)
        let noMethod = try await response(server(), #"{"jsonrpc":"2.0","id":"x"}"#)
        #expect(errorCode(noMethod) == -32600)
        #expect(noMethod["id"] as? String == "x")
    }

    @Test func pingAnswersEmpty() async throws {
        let reply = try await response(server(), request("ping", id: "abc"))
        #expect(reply["id"] as? String == "abc")
        #expect((reply["result"] as? [String: Any])?.isEmpty == true)
    }

    @Test func toolsListNamesTheFourTools() async throws {
        let reply = try await response(server(), request("tools/list"))
        let tools = try #require((reply["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        #expect(tools.map { $0["name"] as? String } == ["show_file_format", "read_show", "write_show", "check_show"])
        let write = try #require(tools.first { $0["name"] as? String == "write_show" })
        #expect((write["inputSchema"] as? [String: Any])?["required"] as? [String] == ["path", "show"])
    }

    @Test func unknownToolIsAProtocolErrorButBadArgumentsAreAToolError() async throws {
        let unknown = try await response(
            server(), request("tools/call", params: ["name": "delete_show", "arguments": [String: Any]()]))
        #expect(errorCode(unknown) == -32602)
        let missing = try await call(server(), "read_show", [:])
        #expect(missing.isError)
        #expect(missing.text.contains("path"))
    }
}

@Suite struct MCPToolTests {
    var movie: [String: Any] { ["format": 1, "title": "T", "items": [[String: Any]]()] }

    @Test func showFileFormatFailsWhenTheBundleLacksIt() async throws {
        #expect(try await call(server(format: nil), "show_file_format", [:]).isError)
    }

    @Test func writeRefusesOtherNamesMissingFoldersAndRelativePaths() async throws {
        try await withAsyncTempDir { dir in
            for path in ["a.json", "a.movie.json.txt", "missing/a.movie.json"].map({ dir.path + "/" + $0 }) {
                let result = try await call(server(), "write_show", ["path": path, "show": movie])
                #expect(result.isError && result.text.hasPrefix("Not written"), "\(path)")
            }
            let relative = try await call(server(), "write_show", ["path": "shows/a.movie.json", "show": movie])
            #expect(relative.isError && relative.text.contains("relative"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }
    }

    @Test(arguments: [
        ("a.concert.json", #"{"format":1,"title":"T","items":[{"type":"clip","file":"01_a.mp4"}]}"#),
        ("a.concert.json", #"{"format":1,"title":"T","items":[{"type":"movie","file":"gone.movie.json"}]}"#),
        ("a.concert.json", #"{"format":1,"title":"T","items":[{"type":"movie","file":"nested.movie.json"}]}"#),
        ("a.movie.json", #"{"format":1,"title":"T","items":[{"type":"movie","file":"b.movie.json"}]}"#),
        ("a.movie.json", #"{"format":2,"title":"T","items":[]}"#),
        ("a.movie.json", #"{"format":1,"title":"T","items":[{"type":"hologram"}]}"#),
        ("a.movie.json", #"{"format":1,"items":[]}"#),
    ])
    func anInvalidShowLeavesTheFileUntouched(name: String, show: String) async throws {
        try await withAsyncTempDir { dir in
            let url = dir.appendingPathComponent(name)
            let before = Data(#"{ "format": 1, "title": "Before" }"#.utf8)
            try before.write(to: url)
            // A movie ref must load as a movie, not just exist.
            try write(
                #"{"format":1,"title":"N","items":[{"type":"movie","file":"x.movie.json"}]}"#,
                to: dir.appendingPathComponent("nested.movie.json"))
            let object = try JSONSerialization.jsonObject(with: Data(show.utf8))

            let result = try await call(server(), "write_show", ["path": url.path, "show": object])

            #expect(result.isError && result.text.hasPrefix("Not written"))
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test func absolutePathsInsideTheFolderTreeAreStoredRelative() async throws {
        try await withAsyncTempDir { dir in
            for name in ["clips/01_a.mp4", "logos/orchestra.png", "slots/thanks.mp4"] {
                try write("", to: dir.appendingPathComponent(name))
            }
            let movieURL = dir.appendingPathComponent("clips/clips.movie.json")
            let outside = "/Volumes/Show Drive/02_b.mp4"
            let movie: [String: Any] = [
                "format": 1, "title": "Clips",
                "items": [
                    ["type": "clip", "file": dir.path + "/clips/01_a.mp4"], ["type": "clip", "file": outside],
                    ["type": "clip", "file": "03_c.mp4"],
                ],
            ]

            let written = try await call(server(), "write_show", ["path": movieURL.path, "show": movie])

            #expect(!written.isError)
            #expect(try jsonObject(Data(written.text.utf8))["show"] as? String == movieURL.path)
            #expect(
                try ShowLoader.loadMovie(at: movieURL).items == [
                    .clip(Clip(file: "01_a.mp4")), .clip(Clip(file: outside)), .clip(Clip(file: "03_c.mp4")),
                ])

            let concertURL = dir.appendingPathComponent("gala.concert.json")
            let concert: [String: Any] = [
                "format": 1, "title": "Gala",
                "logos": [dir.path + "/logos/orchestra.png", "/Library/Logos/sponsor.png"],
                "slots": [NSNull(), ["name": "Thanks", "file": dir.path + "/slots/thanks.mp4"]] as [Any],
                "items": [["type": "movie", "file": movieURL.path]],
            ]
            let concertWritten = try await call(server(), "write_show", ["path": concertURL.path, "show": concert])
            #expect(!concertWritten.isError)
            let saved = try ShowLoader.loadConcert(at: concertURL).concert
            #expect(saved.items == [.movie(MovieRef(file: "clips/clips.movie.json"))])
            #expect(saved.logos == [.image("logos/orchestra.png"), .image("/Library/Logos/sponsor.png")])
            #expect(saved.slots == [.useDefault, .own(SlotEntry(name: "Thanks", file: "slots/thanks.mp4"))])
        }
    }

    @Test func aFileOpenInTheRunningAppIsRefused() async throws {
        try await withAsyncTempDir { dir in
            let movieURL = dir.appendingPathComponent("a.movie.json")
            let concertURL = dir.appendingPathComponent("gala.concert.json")
            try ShowLoader.save(Movie(title: "A"), to: movieURL)
            try ShowLoader.save(Concert(title: "Gala", items: [.movie(MovieRef(file: "a.movie.json"))]), to: concertURL)
            let alias = dir.appendingPathComponent("alias")
            try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: dir)
            let before = try Data(contentsOf: movieURL)
            let changed: [String: Any] = ["format": 1, "title": "Changed"]

            // The open show itself, named through a symlink, and a movie of the open concert.
            for open in [
                [alias.appendingPathComponent("a.movie.json")], MCPServer.openFiles(showPath: concertURL.path),
            ] {
                let result = try await call(server(open: open), "write_show", ["path": movieURL.path, "show": changed])
                #expect(result.isError && result.text.contains("close the show in Player"))
            }
            #expect(try Data(contentsOf: movieURL) == before)

            let other = try await call(
                server(open: [dir.appendingPathComponent("other.movie.json")]), "write_show",
                ["path": movieURL.path, "show": changed])
            #expect(!other.isError)
            #expect(try ShowLoader.loadMovie(at: movieURL).title == "Changed")
        }
    }

    @Test func whenTheAppCannotTellWhatIsOpenNothingIsWritten() async throws {
        try await withAsyncTempDir { dir in
            let url = dir.appendingPathComponent("a.movie.json")
            let result = try await call(server(open: nil), "write_show", ["path": url.path, "show": movie])
            #expect(result.isError && result.text.contains(".app/Contents/MacOS"))
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func aSymlinkedShowFileIsWrittenThrough() async throws {
        try await withAsyncTempDir { dir in
            let real = dir.appendingPathComponent("gala-2026.movie.json")
            let link = dir.appendingPathComponent("current.movie.json")
            try ShowLoader.save(Movie(title: "A"), to: real)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

            let result = try await call(
                server(), "write_show", ["path": link.path, "show": ["format": 1, "title": "Changed"]])

            #expect(!result.isError)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == real.path)
            #expect(try ShowLoader.loadMovie(at: real).title == "Changed")
            #expect(try ShowLoader.loadMovie(at: URL(fileURLWithPath: real.path + ".trashed")).title == "A")
        }
    }

    @Test func overwritingMovesThePreviousFileToTheTrashFirst() async throws {
        try await withAsyncTempDir { dir in
            let bin = dir.appendingPathComponent("Trash")
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            let server = server(trash: { url in
                let target = bin.appendingPathComponent(url.lastPathComponent)
                try FileManager.default.moveItem(at: url, to: target)
                return target
            })
            let url = dir.appendingPathComponent("a.movie.json")

            let first = try await call(
                server, "write_show", ["path": url.path, "show": ["format": 1, "title": "One"]])
            #expect(!first.isError && !first.text.contains("Trash"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: bin.path).isEmpty)
            let before = try Data(contentsOf: url)

            let second = try await call(
                server, "write_show", ["path": url.path, "show": ["format": 1, "title": "Two"]])

            #expect(!second.isError && second.text.hasPrefix("The previous a.movie.json is in the Trash"))
            #expect(try Data(contentsOf: bin.appendingPathComponent("a.movie.json")) == before)
            #expect(try ShowLoader.loadMovie(at: url).title == "Two")
        }
    }

    @Test func tildePathsInsideAShowAreExpanded() async throws {
        try await withAsyncTempDir { dir in
            let url = dir.appendingPathComponent("a.movie.json")
            let show: [String: Any] = [
                "format": 1, "title": "T", "items": [["type": "clip", "file": "~/Movies/Gala/01_a.mp4"]],
            ]

            let result = try await call(server(), "write_show", ["path": url.path, "show": show])

            #expect(!result.isError)
            #expect(
                try ShowLoader.loadMovie(at: url).items == [
                    .clip(Clip(file: NSHomeDirectory() + "/Movies/Gala/01_a.mp4"))
                ])
        }
    }

    @Test func anOpenFolderIsItsMovieFile() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("Showman")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            #expect(MCPServer.openFiles(showPath: folder.path) == [ShowLoader.movieFile(inFolder: folder)])
        }
    }

    @Test func readingAFolderWithoutAMovieFileReturnsTheGeneratedMovieUnsaved() async throws {
        try await withAsyncTempDir { dir in
            let folder = dir.appendingPathComponent("Showman")
            for name in ["02_b.mp4", "01_a.mp4"] { try write("", to: folder.appendingPathComponent(name)) }

            let result = try await call(server(), "read_show", ["path": folder.path])

            #expect(!result.isError)
            let read = try jsonObject(Data(result.text.utf8))
            #expect(read["path"] as? String == ShowLoader.movieFile(inFolder: folder).path)
            #expect(read["saved"] as? Bool == false)
            let show = try JSONSerialization.data(withJSONObject: try #require(read["show"]))
            #expect(
                try JSONDecoder().decode(Movie.self, from: show)
                    == Movie(title: "Showman", items: [.clip(Clip(file: "01_a.mp4")), .clip(Clip(file: "02_b.mp4"))]))
            #expect(
                try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == ["01_a.mp4", "02_b.mp4"])

            try ShowLoader.save(Movie(title: "Edited"), to: ShowLoader.movieFile(inFolder: folder))
            let saved = try jsonObject(Data(try await call(server(), "read_show", ["path": folder.path]).text.utf8))
            #expect(saved["saved"] as? Bool == true)
            #expect((saved["show"] as? [String: Any])?["title"] as? String == "Edited")
        }
    }

    @Test func checkReturnsTheInjectedReportAndAShowThatCannotLoadIsNoToolError() async throws {
        let server = MCPServer(
            name: "Player", version: "1", showFileFormat: { nil },
            check: { CheckReport(show: $0, error: "cannot load") },
            openFiles: { [] }, trash: moveAside, log: { _ in })

        let result = try await call(server, "check_show", ["path": "~/Gala/gala.concert.json"])

        #expect(!result.isError)
        let report = try jsonObject(Data(result.text.utf8))
        #expect(report["result"] as? String == "error")
        #expect(report["show"] as? String == NSHomeDirectory() + "/Gala/gala.concert.json")
        #expect(try await call(server, "check_show", ["path": "Gala/gala.concert.json"]).isError)
    }
}
