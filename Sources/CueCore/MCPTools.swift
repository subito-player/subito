import Foundation

struct ToolError: Error {
    var message: String

    init(_ message: String) {
        self.message = message
    }
}

private struct ReadResult<Show: Encodable>: Encodable {
    var path: String
    var saved: Bool
    var show: Show
}

extension MCPServer {
    func call(_ name: String, _ raw: Any?) async -> (text: String, isError: Bool)? {
        var path = "-"
        let text: String
        let outcome: String
        do {
            guard let arguments = raw == nil ? [:] : raw as? [String: Any] else {
                throw ToolError("arguments must be a JSON object.")
            }
            switch name {
            case "show_file_format":
                guard let format = showFileFormat() else {
                    throw ToolError("show-files.md is missing from the app bundle: rebuild the app with make app.")
                }
                (text, outcome) = (format, "ok")
            case "read_show":
                let url = try Self.fileURL(arguments["path"])
                path = url.path
                (text, outcome) = (try Self.read(url), "ok")
            case "write_show":
                let url = try Self.fileURL(arguments["path"])
                path = url.path
                let trashed: URL?
                do {
                    trashed = try write(arguments["show"], to: url)
                } catch {
                    throw ToolError("Not written: \(Self.message(error))")
                }
                let report = await check(url.path)
                let note = trashed.map {
                    "The previous \(url.lastPathComponent) is in the Trash as \($0.lastPathComponent).\n"
                }
                (text, outcome) = (
                    (note ?? "") + (try Self.text(report)),
                    "written\(trashed == nil ? "" : ", previous in the Trash"), check \(report.result.rawValue)"
                )
            case "check_show":
                let url = try Self.fileURL(arguments["path"])
                path = url.path
                let report = await check(url.path)
                (text, outcome) = (try Self.text(report), "check \(report.result.rawValue)")
            default:
                return nil
            }
        } catch {
            log("mcp \(name) \(path): error: \(Self.message(error))")
            return (Self.message(error), true)
        }
        log("mcp \(name) \(path): \(outcome)")
        return (text, false)
    }

    // What the running app may save over: its open show and, for a concert, the concert's movies.
    public static func openFiles(showPath: String?) -> [URL] {
        guard let showPath else { return [] }
        var url = URL(fileURLWithPath: showPath).standardizedFileURL
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
            url = ShowLoader.movieFile(inFolder: url)
        }
        guard url.lastPathComponent.hasSuffix(".concert.json"),
            let concert = try? ShowLoader.decode(Concert.self, from: url)
        else { return [url] }
        return [url]
            + concert.items.compactMap { item in
                if case .movie(let ref) = item { ShowLoader.resolve(ref.file, relativeTo: url) } else { nil }
            }
    }

    // The client's working folder is unknown, so a relative path could name any file.
    static func fileURL(_ value: Any?) throws -> URL {
        guard let path = value as? String, !path.isEmpty else {
            throw ToolError("path is required: an absolute path or one starting with ~.")
        }
        let expanded = NSString(string: path).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            throw ToolError("\(path) is relative: give an absolute path or one starting with ~.")
        }
        return URL(fileURLWithPath: expanded).standardizedFileURL
    }

    static func read(_ url: URL) throws -> String {
        let document = try ShowDocument.loadReadOnly(url)
        let file = document.url.path
        let saved = FileManager.default.fileExists(atPath: file)
        if let concert = document.concert {
            return try ShowLoader.text(ReadResult(path: file, saved: saved, show: concert))
        }
        return try ShowLoader.text(ReadResult(path: file, saved: saved, show: document.movies[document.url]))
    }

    // Checked with the loader's own rules before anything touches the disk, so an invalid show is never written.
    func write(_ value: Any?, to url: URL) throws -> URL? {
        let name = url.lastPathComponent
        let isConcert = name.hasSuffix(".concert.json")
        guard isConcert || name.hasSuffix(".movie.json") else {
            throw ToolError("\(name) is not a show file name: it must end in .movie.json or .concert.json.")
        }
        let folder = url.deletingLastPathComponent()
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isFolder), isFolder.boolValue else {
            throw ToolError("the folder \(folder.path) does not exist.")
        }
        guard let show = value as? [String: Any] else {
            throw ToolError("show must be the complete movie or concert as a JSON object.")
        }
        let data = try JSONSerialization.data(withJSONObject: show)
        // An atomic save replaces a symlink with a plain file, so the write goes to the file it points at.
        let destination = url.resolvingSymlinksInPath()
        // The stored paths are validated, so a ~ or absolute movie ref is checked as the app will read it.
        let save: () throws -> Void
        if isConcert {
            let concert = Self.storingRelative(try ShowLoader.decode(Concert.self, from: data, file: url), at: url)
            _ = try ShowLoader.validate(concert, at: url)
            save = { try ShowLoader.save(concert, to: destination) }
        } else {
            let movie = Self.storingRelative(try ShowLoader.decode(Movie.self, from: data, file: url), at: url)
            _ = try ShowLoader.validate(movie, at: url)
            save = { try ShowLoader.save(movie, to: destination) }
        }
        try refuseIfOpen(url)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: destination.path, isDirectory: &isDirectory)
        let trashed = exists && !isDirectory.boolValue ? try trash(destination) : nil
        do {
            try save()
        } catch {
            if let trashed { try? FileManager.default.moveItem(at: trashed, to: destination) }
            throw error
        }
        return trashed
    }

    // The app keeps its show in memory and saves the whole file on its next edit, over anything written here.
    private func refuseIfOpen(_ url: URL) throws {
        // Unknown counts as open: a write the app later saves over is lost without a word.
        guard let open = openFiles() else {
            throw ToolError(
                "this server cannot tell whether \(url.lastPathComponent) is open in the app. Start it from inside "
                    + "the app bundle (.app/Contents/MacOS), not from a bare build binary.")
        }
        let target = Self.canonical(url)
        guard open.contains(where: { Self.canonical($0) == target }) else { return }
        throw ToolError(
            "\(url.lastPathComponent) is open in \(name), and the app's next save would overwrite this change. "
                + "Ask the user to close the show in \(name) (open another show or quit \(name)), then retry.")
    }

    // String == ignores NFC/NFD differences, as the file system does.
    private static func canonical(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    static func storingRelative(_ movie: Movie, at url: URL) -> Movie {
        var movie = movie
        movie.items = movie.items.map { item in
            guard case .clip(var clip) = item else { return item }
            clip.file = stored(clip.file, in: url)
            return .clip(clip)
        }
        return movie
    }

    static func storingRelative(_ concert: Concert, at url: URL) -> Concert {
        var concert = concert
        concert.items = concert.items.map { item in
            guard case .movie(var ref) = item else { return item }
            ref.file = stored(ref.file, in: url)
            return .movie(ref)
        }
        concert.logos = concert.logos.map { logo in
            guard var logo else { return nil }
            logo.path = stored(logo.path, in: url)
            return logo
        }
        concert.slots = concert.slots.map { slot in
            guard case .own(var entry) = slot else { return slot }
            entry.file = stored(entry.file, in: url)
            return .own(entry)
        }
        return concert
    }

    // The app reads ~ as a folder name, so it is expanded; inside the file's folder tree becomes relative.
    private static func stored(_ path: String, in file: URL) -> String {
        let expanded = path.hasPrefix("~") ? NSString(string: path).expandingTildeInPath : path
        guard expanded.hasPrefix("/") else { return path }
        let relative = ShowLoader.relativePath(to: URL(fileURLWithPath: expanded), from: file)
        return relative.hasPrefix("/") ? expanded : relative
    }

    private static func text(_ report: CheckReport) throws -> String {
        String(decoding: try report.json(), as: UTF8.self)
    }

    private static func message(_ error: Error) -> String {
        switch error {
        case let error as ToolError: error.message
        case let error as ShowError: error.description
        default: error.localizedDescription
        }
    }
}
