import Foundation

// Wires the --mcp server into Claude: a Desktop Extension (.mcpb) and the Claude Code command.
public enum ClaudeSetup {
    public struct PackFailure: Error, Equatable, CustomStringConvertible {
        public var status: Int32
        public var message: String

        public var description: String { "ditto exited \(status): \(message)" }
    }

    public static let iconFile = "icon.png"
    static let manifestFile = "manifest.json"

    private struct Manifest: Encodable {
        struct Author: Encodable { var name: String }
        struct Compatibility: Encodable { var platforms: [String] }
        struct Server: Encodable {
            struct Config: Encodable {
                var command: String
                var args: [String]
            }
            var type: String
            var entryPoint: String
            var mcpConfig: Config
        }

        var manifestVersion: String
        var name: String
        var displayName: String
        var version: String
        var description: String
        var author: Author
        var server: Server
        var compatibility: Compatibility
        var icon: String?
    }

    // Remove first because `claude mcp add` refuses an existing name; the path is single-quoted for the shell.
    public static func codeCommand(name: String, executable: String) -> String {
        let server = name.lowercased()
        let quoted = "'" + executable.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return "claude mcp remove --scope user \(server) 2>/dev/null; "
            + "claude mcp add --scope user \(server) -- \(quoted) --mcp"
    }

    // A dmg mount or a Gatekeeper-translocated copy is gone after a reboot or an eject, so nothing may point at it.
    public static func isTemporaryLocation(_ executable: String) -> Bool {
        executable.hasPrefix("/Volumes/") || executable.contains("/AppTranslocation/")
    }

    // Binary type: Claude Desktop runs the command directly, so the extension points at the app's own executable.
    public static func manifest(name: String, version: String, executable: String, icon: Bool) -> Data {
        let manifest = Manifest(
            manifestVersion: "0.3",
            name: name.lowercased(),
            displayName: name,
            version: version,
            description: "Read, write and check \(name) show files.",
            author: .init(name: name),
            server: .init(
                type: "binary", entryPoint: executable, mcpConfig: .init(command: executable, args: ["--mcp"])),
            compatibility: .init(platforms: ["darwin"]),
            icon: icon ? iconFile : nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        // Strings only, so encoding cannot fail.
        return try! encoder.encode(manifest) + Data("\n".utf8)
    }

    // The zip holds the folder's contents, so manifest.json sits at its root as Claude Desktop expects.
    public static func pack(manifest: Data, icon: Data?, to file: URL) throws {
        let files = FileManager.default
        let staging = files.temporaryDirectory.appendingPathComponent("mcpb-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: staging) }
        try manifest.write(to: staging.appendingPathComponent(manifestFile))
        if let icon { try icon.write(to: staging.appendingPathComponent(iconFile)) }
        try? files.removeItem(at: file)
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        // Without these, ditto adds ._ AppleDouble entries for the provenance xattr the system puts on new files.
        ditto.arguments = ["-c", "-k", "--norsrc", "--noextattr", staging.path, file.path]
        let errors = Pipe()
        ditto.standardError = errors
        try ditto.run()
        let message = errors.fileHandleForReading.readDataToEndOfFile()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else {
            throw PackFailure(
                status: ditto.terminationStatus,
                message: String(decoding: message, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
