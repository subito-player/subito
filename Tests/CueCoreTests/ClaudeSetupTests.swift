import Foundation
import Testing

@testable import CueCore

private func run(_ tool: String, _ arguments: [String]) throws -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    try process.run()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    return data
}

private func entries(_ data: Data) -> Set<String> {
    Set(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init))
}

private func json(_ data: Data) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
}

@Suite struct ClaudeSetupTests {
    private let executable = "/Applications/Subito.app/Contents/MacOS/Subito"

    @Test func theCodeCommandReplacesAnEarlierSetupOfTheSameName() {
        #expect(
            ClaudeSetup.codeCommand(name: "Subito", executable: executable)
                == "claude mcp remove --scope user subito 2>/dev/null; "
                + "claude mcp add --scope user subito -- '/Applications/Subito.app/Contents/MacOS/Subito' --mcp")
    }

    // The shell must hand claude the path as one argument, whatever it holds, and add even when remove fails.
    @Test(arguments: [
        "/Applications/Subito.app/Contents/MacOS/Subito",
        "/Users/me/My Apps/Subito.app/Contents/MacOS/Subito",
        "/Users/me/Próba koncert/Subito".precomposedStringWithCanonicalMapping,
        "/Users/me/Bob's Mac/Subito",
        "/Users/me/$HOME `date` \"x\"/Subito",
    ])
    func theCodeCommandSurvivesTheShell(path: String) throws {
        let command = ClaudeSetup.codeCommand(name: "Subito", executable: path)
        let script = "claude() { echo call; printf '%s\\n' \"$@\"; [ \"$2\" != remove ]; }; \(command)"
        let calls = String(decoding: try run("/bin/sh", ["-c", script]), as: UTF8.self)
        let remove = ["call", "mcp", "remove", "--scope", "user", "subito"]
        let add = ["call", "mcp", "add", "--scope", "user", "subito", "--", path, "--mcp"]
        #expect(calls == (remove + add).joined(separator: "\n") + "\n")
    }

    @Test(arguments: [
        ("/Volumes/Subito 0.3.1/Subito.app/Contents/MacOS/Subito", true),
        ("/private/var/folders/ab/cd/AppTranslocation/0A1B/d/Subito.app/Contents/MacOS/Subito", true),
        ("/Applications/Subito.app/Contents/MacOS/Subito", false),
        ("/Users/me/dev/Subito/build/Subito.app/Contents/MacOS/Subito", false),
    ])
    func aMountedOrTranslocatedAppIsTemporary(path: String, temporary: Bool) {
        #expect(ClaudeSetup.isTemporaryLocation(path) == temporary)
    }

    @Test func theManifestRunsTheExecutableDirectly() throws {
        let manifest = try json(
            ClaudeSetup.manifest(name: "Subito", version: "0.3.1", executable: executable, icon: true))
        #expect(manifest["manifest_version"] as? String == "0.3")
        #expect(manifest["name"] as? String == "subito")
        #expect(manifest["display_name"] as? String == "Subito")
        #expect(manifest["version"] as? String == "0.3.1")
        #expect((manifest["author"] as? [String: Any])?["name"] as? String == "Subito")
        #expect((manifest["compatibility"] as? [String: Any])?["platforms"] as? [String] == ["darwin"])
        let server = try #require(manifest["server"] as? [String: Any])
        #expect(server["type"] as? String == "binary")
        #expect(server["entry_point"] as? String == executable)
        let config = try #require(server["mcp_config"] as? [String: Any])
        #expect(config["command"] as? String == executable)
        #expect(config["args"] as? [String] == ["--mcp"])
    }

    @Test func theIconKeyIsThereOnlyWithAnIcon() throws {
        let with = try json(ClaudeSetup.manifest(name: "Subito", version: "1", executable: executable, icon: true))
        let without = try json(ClaudeSetup.manifest(name: "Subito", version: "1", executable: executable, icon: false))
        #expect(with["icon"] as? String == "icon.png")
        #expect(without["icon"] == nil)
    }

    @Test func theZipHoldsTheFilesAtItsRoot() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Subito.mcpb")
            let manifest = ClaudeSetup.manifest(name: "Subito", version: "1", executable: executable, icon: true)
            try ClaudeSetup.pack(manifest: manifest, icon: Data([1, 2, 3]), to: file)
            #expect(try entries(run("/usr/bin/zipinfo", ["-1", file.path])) == ["manifest.json", "icon.png"])
            #expect(try run("/usr/bin/unzip", ["-p", file.path, "manifest.json"]) == manifest)
            #expect(try run("/usr/bin/unzip", ["-p", file.path, "icon.png"]) == Data([1, 2, 3]))
        }
    }

    @Test func theZipHasNoIconWhenThereIsNone() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Subito.mcpb")
            try ClaudeSetup.pack(manifest: Data("{}".utf8), icon: nil, to: file)
            #expect(try entries(run("/usr/bin/zipinfo", ["-1", file.path])) == ["manifest.json"])
        }
    }

    @Test func packingAgainReplacesTheFile() throws {
        try withTempDir { dir in
            let file = dir.appendingPathComponent("Subito.mcpb")
            try ClaudeSetup.pack(manifest: Data("one".utf8), icon: Data([1]), to: file)
            try ClaudeSetup.pack(manifest: Data("two".utf8), icon: nil, to: file)
            #expect(try entries(run("/usr/bin/zipinfo", ["-1", file.path])) == ["manifest.json"])
            #expect(try run("/usr/bin/unzip", ["-p", file.path, "manifest.json"]) == Data("two".utf8))
        }
    }

    @Test func aFailingZipToolThrows() throws {
        try withTempDir { dir in
            let blocker = dir.appendingPathComponent("a file")
            try Data().write(to: blocker)
            let file = blocker.appendingPathComponent("Subito.mcpb")
            #expect(throws: ClaudeSetup.PackFailure.self) {
                try ClaudeSetup.pack(manifest: Data("{}".utf8), icon: nil, to: file)
            }
        }
    }
}
