import Foundation

public enum ShowError: Error, Equatable, CustomStringConvertible {
    case fileMissing(URL)
    case invalidJSON(file: URL, message: String)
    case unsupportedFormat(file: URL, format: Int)
    case movieContainsMovie(file: URL)
    case concertHasClip(file: URL)
    case movieFileMissing(concert: URL, path: String)

    public var description: String {
        switch self {
        case .fileMissing(let url):
            "Cannot read \(url.path): the file is missing or unreadable."
        case .invalidJSON(let file, let message):
            "\(file.lastPathComponent) is not valid: \(message)"
        case .unsupportedFormat(let file, let format):
            "\(file.lastPathComponent) uses format \(format), but this version only reads format \(currentFormat). Update the app."
        case .movieContainsMovie(let file):
            "\(file.lastPathComponent) is a movie but contains another movie. Movies cannot be nested."
        case .concertHasClip(let file):
            "\(file.lastPathComponent) is a concert but contains a clip. Put clips in a movie and add the movie."
        case .movieFileMissing(let concert, let path):
            "\(concert.lastPathComponent) refers to the movie \(path), which does not exist."
        }
    }
}

public struct LoadedConcert: Equatable, Sendable {
    public var concert: Concert
    public var url: URL
    // Keyed by the movie item's resolved file URL.
    public var movies: [URL: Movie]

    public init(concert: Concert, url: URL, movies: [URL: Movie]) {
        self.concert = concert
        self.url = url
        self.movies = movies
    }
}

public struct Cue: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case clip(Clip, URL)
        case black
        case breakScreen(BreakItem)
        /// 1-based index into `Concert.logos`.
        case logo(Int)
    }

    public var kind: Kind
    // 0-based index among the concert's movies; nil for concert-level items.
    public var movieIndex: Int?

    public init(kind: Kind, movieIndex: Int?) {
        self.kind = kind
        self.movieIndex = movieIndex
    }
}

public enum ShowLoader {
    private static let clipExtensions: Set<String> = ["mp4", "mov", "m4v"]

    public static func resolve(_ path: String, relativeTo file: URL) -> URL {
        URL(fileURLWithPath: path, isDirectory: false, relativeTo: file.deletingLastPathComponent()).absoluteURL
    }

    public static func loadMovie(at url: URL) throws -> Movie {
        let movie = try decode(Movie.self, from: url)
        for case .movie in movie.items { throw ShowError.movieContainsMovie(file: url) }
        return movie
    }

    public static func loadConcert(at url: URL) throws -> LoadedConcert {
        let concert = try decode(Concert.self, from: url)
        var movies: [URL: Movie] = [:]
        for item in concert.items {
            switch item {
            case .clip:
                throw ShowError.concertHasClip(file: url)
            case .movie(let ref):
                let movieURL = resolve(ref.file, relativeTo: url)
                guard FileManager.default.fileExists(atPath: movieURL.path) else {
                    throw ShowError.movieFileMissing(concert: url, path: ref.file)
                }
                movies[movieURL] = try loadMovie(at: movieURL)
            default: continue
            }
        }
        return LoadedConcert(concert: concert, url: url, movies: movies)
    }

    public static func save(_ movie: Movie, to url: URL) throws {
        try write(movie, to: url)
    }

    public static func save(_ concert: Concert, to url: URL) throws {
        try write(concert, to: url)
    }

    public static func movie(fromFolder folder: URL) throws -> Movie {
        let entries = try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { clipExtensions.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
            .compactMap { name -> (number: Int, name: String)? in
                Clip(file: name).resolvedNumber.map { ($0, name) }
            }
            .sorted { ($0.number, $0.name) < ($1.number, $1.name) }
        return Movie(title: folder.lastPathComponent, items: entries.map { .clip(Clip(file: $0.name)) })
    }

    public static func importFolder(_ folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(folder.lastPathComponent + ".movie.json")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        try save(movie(fromFolder: folder), to: url)
        return url
    }

    public static func flatten(_ loaded: LoadedConcert) -> [Cue] {
        var result: [Cue] = []
        var movieIndex = 0
        for item in loaded.concert.items {
            guard case .movie(let ref) = item else {
                result += cue(for: item, movieIndex: nil, base: loaded.url)
                continue
            }
            let movieURL = resolve(ref.file, relativeTo: loaded.url)
            if let movie = loaded.movies[movieURL] {
                result += expand(movie, at: movieURL, movieIndex: movieIndex)
            }
            movieIndex += 1
        }
        return result
    }

    public static func flatten(movie: Movie, at url: URL) -> [Cue] {
        expand(movie, at: url, movieIndex: 0)
    }

    private static func expand(_ movie: Movie, at url: URL, movieIndex: Int) -> [Cue] {
        movie.items.flatMap { cue(for: $0, movieIndex: movieIndex, base: url) }
    }

    private static func cue(for item: Item, movieIndex: Int?, base: URL) -> [Cue] {
        let kind: Cue.Kind
        switch item {
        case .clip(let clip): kind = .clip(clip, resolve(clip.file, relativeTo: base))
        case .black: kind = .black
        case .breakScreen(let item): kind = .breakScreen(item)
        case .logo(let item): kind = .logo(item.logo)
        case .movie: return []
        }
        return [Cue(kind: kind, movieIndex: movieIndex)]
    }

    private struct Header: Decodable {
        var format: Int
    }

    private static func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        guard let data = try? Data(contentsOf: url) else { throw ShowError.fileMissing(url) }
        let decoder = JSONDecoder()
        do {
            // Header first so a newer format reports "update the app" instead of a parse error.
            let format = try decoder.decode(Header.self, from: data).format
            if format > currentFormat { throw ShowError.unsupportedFormat(file: url, format: format) }
            return try decoder.decode(T.self, from: data)
        } catch let error as ShowError {
            throw error
        } catch {
            throw ShowError.invalidJSON(file: url, message: describe(error))
        }
    }

    private static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        try data.write(to: url, options: .atomic)
    }

    static func describe(_ error: Error) -> String {
        let context: DecodingError.Context
        let summary: String
        switch error as? DecodingError {
        case .keyNotFound(let key, let found):
            context = found
            summary = "missing \"\(key.stringValue)\""
        case .typeMismatch(_, let found), .valueNotFound(_, let found), .dataCorrupted(let found):
            context = found
            summary = found.debugDescription
        default:
            return error.localizedDescription
        }
        let path = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return path.isEmpty ? summary : "\(summary) at \(path)"
    }
}
