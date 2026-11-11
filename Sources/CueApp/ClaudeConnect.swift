import AppKit
import CueCore
import Observation

// Built from the running app, so the last setup wins.
@MainActor
@Observable
final class ClaudeConnect {
    enum Note: Equatable {
        case desktopMissing
        case moveToApplications
        case packFailed
        case openFailed
    }

    static let desktopBundleID = "com.anthropic.claudefordesktop"
    static let iconPixels = 512

    private(set) var installNote: Note?
    private(set) var copyNote: Note?
    private(set) var copied = false

    private var executable: String {
        Bundle.main.executablePath ?? CommandLine.arguments[0]
    }

    var codeCommand: String {
        ClaudeSetup.codeCommand(name: AppInfo.name, executable: executable)
    }

    func copyCodeCommand() {
        copied = false
        copyNote = nil
        guard !ClaudeSetup.isTemporaryLocation(executable) else {
            copyNote = .moveToApplications
            Log.info("claude: not copying, running from a temporary location: \(executable)")
            return
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(codeCommand, forType: .string)
        copied = true
        Log.info("claude: code command copied")
    }

    func installInDesktop() {
        installNote = nil
        guard !ClaudeSetup.isTemporaryLocation(executable) else {
            installNote = .moveToApplications
            Log.info("claude: not installing, running from a temporary location: \(executable)")
            return
        }
        guard let desktop = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.desktopBundleID) else {
            installNote = .desktopMissing
            Log.info("claude: Claude Desktop is not installed")
            return
        }
        let icon = Self.iconPNG()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(AppInfo.name).mcpb")
        do {
            let manifest = ClaudeSetup.manifest(
                name: AppInfo.name, version: AppInfo.version ?? "0.0.0", executable: executable, icon: icon != nil)
            try ClaudeSetup.pack(manifest: manifest, icon: icon, to: file)
        } catch {
            installNote = .packFailed
            Log.info("error: cannot create the extension: \(error)")
            return
        }
        // The file stays: Claude Desktop reads it after the open call returns.
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    [file], withApplicationAt: desktop, configuration: NSWorkspace.OpenConfiguration())
                Log.info("claude: extension opened in Claude Desktop: \(file.path)")
            } catch {
                installNote = .openFailed
                Log.info("error: cannot open the extension in Claude Desktop: \(error.localizedDescription)")
            }
        }
    }

    private static func iconPNG() -> Data? {
        guard let icon = NSApp.applicationIconImage,
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: iconPixels, pixelsHigh: iconPixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0)
        else { return nil }
        let size = NSSize(width: iconPixels, height: iconPixels)
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        icon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        return bitmap.representation(using: .png, properties: [:])
    }
}
