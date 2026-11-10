import Foundation

// An item's file (the concert or a movie) and its index among that file's items.
public struct Place: Hashable, Sendable {
    public var file: URL
    public var index: Int

    public init(file: URL, index: Int) {
        self.file = file
        self.index = index
    }
}

// One line of the control list: a movie header or a cue.
public struct Row: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        // 0-based, as in Cue.movieIndex.
        case movie(Int, title: String)
        case cue(Int)
    }

    public var kind: Kind
    // nil for the header of a single open movie, which is no item of any file.
    public var place: Place?
    // The movie file the row belongs to; nil for concert-level items.
    public var movie: URL?

    public init(kind: Kind, place: Place?, movie: URL?) {
        self.kind = kind
        self.place = place
        self.movie = movie
    }
}

public enum EditRefusal: Error, Equatable, Sendable {
    case liveItemLocked
    case movieInMovie
    case clipInConcert
    case noSuchItem
}

public enum Edit: Equatable, Sendable {
    case insert(Item, at: Place)
    case insertClips([URL], at: Place)
    // Into the concert, at that index among its items.
    case insertMovie(Movie, URL, at: Int)
    case delete(Place)
    case move(Place, to: Int)
    case renameConcert(String)
    case renameMovie(URL, String)
    // Blank goes back to the title from the file name.
    case renameClip(Place, String)
    // Blank removes the brief.
    case setBrief(Place, String)
    // Blank goes back to the default break title.
    case setBreakText(Place, String)
    case setClipTimes(Place, plannedEndS: Double?, tailS: Double?)
    case setBreak(Place, minutes: Double, countdown: Bool)
    case setLogo(Place, Int)
    // A converted sibling replaces the clip's file; the list keeps the title it showed.
    case replaceClipFile(Place, URL)
    // The concert's logo number n (1-based); nil clears it. Paths inside the show folder are stored relative.
    case setLogoFile(Int, Logo?)
}

// A concert logo resolved against the concert file.
public enum LogoFile: Equatable, Sendable {
    case image(URL)
    case loop(URL)

    public var url: URL {
        switch self {
        case .image(let url), .loop(let url): url
        }
    }
}

public enum Addition: Sendable {
    case clip, item, movie
}

public struct EditResult: Equatable, Sendable {
    public var document: ShowDocument
    // Old flattened cue index -> new index; nil when the cue was deleted.
    public var indexMap: [Int?]
    // Files to write.
    public var changed: [URL]
    // The moved item, the last inserted one, or the changed one.
    public var touched: Place?
}

// The open show plus its movies; every edit returns a new document and leaves this one alone.
public struct ShowDocument: Equatable, Sendable {
    public let url: URL
    public private(set) var concert: Concert?
    // Keyed by resolved file URL; a single open movie is keyed by `url`.
    public private(set) var movies: [URL: Movie]
    public private(set) var cues: [Cue] = []
    public private(set) var rows: [Row] = []
    private var origins: [Origin] = []

    public init(_ loaded: LoadedConcert) {
        url = loaded.url
        concert = loaded.concert
        movies = loaded.movies
        rebuild()
    }

    public init(movie: Movie, at url: URL) {
        self.url = url
        movies = [url: movie]
        rebuild()
    }

    public static func load(_ url: URL) throws -> ShowDocument {
        var isFolder: ObjCBool = false
        let folder = FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder) && isFolder.boolValue
        if !folder, url.lastPathComponent.hasSuffix(".concert.json") {
            return ShowDocument(try ShowLoader.loadConcert(at: url))
        }
        let (file, movie) = try ShowLoader.openMovie(url)
        return ShowDocument(movie: movie, at: file)
    }

    // Like `load`, but calls only the loaders, so nothing is ever written; a folder without a movie file is read in memory.
    public static func loadReadOnly(_ url: URL) throws -> ShowDocument {
        var isFolder: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isFolder), isFolder.boolValue {
            let file = ShowLoader.movieFile(inFolder: url)
            let exists = FileManager.default.fileExists(atPath: file.path)
            return ShowDocument(
                movie: exists ? try ShowLoader.loadMovie(at: file) : try ShowLoader.movie(fromFolder: url), at: file)
        }
        if url.lastPathComponent.hasSuffix(".concert.json") { return ShowDocument(try ShowLoader.loadConcert(at: url)) }
        return ShowDocument(movie: try ShowLoader.loadMovie(at: url), at: url)
    }

    public var title: String {
        concert?.title ?? movies[url]?.title ?? ""
    }

    // nil for a logo number with no file, which shows black.
    public var logos: [LogoFile?] {
        (concert?.logos ?? []).map { logo in
            guard !logo.path.isEmpty else { return nil }
            let file = ShowLoader.resolve(logo.path, relativeTo: url)
            return if case .loop = logo { .loop(file) } else { .image(file) }
        }
    }

    public func item(at place: Place) -> Item? {
        guard let items = items(in: place.file), items.indices.contains(place.index) else { return nil }
        return items[place.index]
    }

    // The live cue's own item, or the concert entry of the movie it plays from.
    public func isLocked(_ place: Place, live: Int?) -> Bool {
        guard let live, origins.indices.contains(live) else { return false }
        let origin = origins[live]
        if isConcert(place.file) { return origin.concert == place.index }
        return origin.movie == place.file && origin.item == place.index
    }

    // After the selected item in its file; with nothing usable selected, at the end (clips: of the only movie).
    public func insertionPlace(for addition: Addition, selected: Place?) -> Place? {
        let chosen = selected.flatMap { item(at: $0) == nil ? nil : $0 }
        switch addition {
        case .item:
            guard let chosen else { return end(of: url) }
            return Place(file: chosen.file, index: chosen.index + 1)
        case .clip:
            if let chosen, !isConcert(chosen.file) { return Place(file: chosen.file, index: chosen.index + 1) }
            if let chosen, let movie = item(at: chosen).flatMap(movieURL) { return end(of: movie) }
            let files = Set(rows.compactMap(\.movie))
            guard files.count == 1, let only = files.first else { return nil }
            return end(of: only)
        case .movie:
            guard let concert else { return nil }
            if let chosen, isConcert(chosen.file) { return Place(file: url, index: chosen.index + 1) }
            if let chosen, let index = concert.items.firstIndex(where: { movieURL($0) == chosen.file }) {
                return Place(file: url, index: index + 1)
            }
            return end(of: url)
        }
    }

    // A concert item dropped on a row inside a movie lands on that movie's own concert entry.
    public func dropPlace(moving source: Place, onto row: Row) -> Place? {
        guard let target = row.place else { return nil }
        if target.file == source.file { return target }
        guard isConcert(source.file), case .cue(let index) = row.kind, origins.indices.contains(index),
            let entry = origins[index].concert
        else { return nil }
        return Place(file: url, index: entry)
    }

    public func apply(_ edit: Edit, live: Int?) -> Result<EditResult, EditRefusal> {
        switch edit {
        case .insert(let item, let place):
            return insert([item], at: place)
        case .insertClips(let files, let place):
            let clips = files.map { Item.clip(Clip(file: ShowLoader.relativePath(to: $0, from: place.file))) }
            return insert(clips, at: place)
        case .insertMovie(let movie, let file, let index):
            guard concert != nil else { return .failure(.movieInMovie) }
            let ref = MovieRef(file: ShowLoader.relativePath(to: file, from: url))
            var document = self
            // A movie already in the show keeps its in-memory copy, the one the editor saved last.
            if document.movies[resolve(ref)] == nil { document.movies[resolve(ref)] = movie }
            return document.insert([.movie(ref)], at: Place(file: url, index: index))
        case .delete(let place):
            guard var items = items(in: place.file), items.indices.contains(place.index) else {
                return .failure(.noSuchItem)
            }
            guard !isLocked(place, live: live) else { return .failure(.liveItemLocked) }
            var order = oldOrder(items.count)
            items.remove(at: place.index)
            order.remove(at: place.index)
            return restructure(place.file, items, order, touched: nil)
        case .move(let place, let target):
            guard var items = items(in: place.file), items.indices.contains(place.index),
                items.indices.contains(target)
            else { return .failure(.noSuchItem) }
            guard !isLocked(place, live: live) else { return .failure(.liveItemLocked) }
            items.insert(items.remove(at: place.index), at: target)
            var order = oldOrder(items.count)
            order.insert(order.remove(at: place.index), at: target)
            return restructure(place.file, items, order, touched: Place(file: place.file, index: target))
        case .renameConcert(let title):
            guard concert != nil else { return .failure(.noSuchItem) }
            var document = self
            document.concert?.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return .success(unchanged(document, file: url))
        case .renameMovie(let file, let title):
            guard movies[file] != nil else { return .failure(.noSuchItem) }
            var document = self
            document.movies[file]?.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            document.rebuild()
            return .success(unchanged(document, file: file))
        case .renameClip(let place, let title):
            return modifyClip(place) { clip in clip.title = Self.text(title) }
        case .setBrief(let place, let brief):
            return modifyClip(place) { clip in clip.brief = Self.text(brief) }
        case .setBreakText(let place, let text):
            return modifyBreak(place) { item in item.text = Self.text(text) }
        case .setClipTimes(let place, let plannedEndS, let tailS):
            return modifyClip(place) { clip in
                clip.plannedEndS = plannedEndS
                clip.tailS = tailS
            }
        case .setBreak(let place, let minutes, let countdown):
            return modifyBreak(place) { item in
                item.minutes = minutes
                item.countdown = countdown
            }
        case .setLogo(let place, let number):
            guard case .logo? = item(at: place) else { return .failure(.noSuchItem) }
            return modify(place, to: .logo(LogoItem(logo: number)))
        case .replaceClipFile(let place, let file):
            return modifyClip(place) { clip in
                let title = clip.resolvedTitle
                // Only the name changes, so the folder part stays as written, relative or absolute.
                let folder = clip.file.lastIndex(of: "/").map { String(clip.file[...$0]) } ?? ""
                clip.file = folder + file.lastPathComponent
                if clip.resolvedTitle != title { clip.title = title }
            }
        case .setLogoFile(let number, let logo):
            guard var logos = concert?.logos, number >= 1 else { return .failure(.noSuchItem) }
            // An empty path keeps the numbers after it in place; v0.1 reads it as a logo that shows black.
            let none = Logo.image("")
            while logos.count < number { logos.append(none) }
            logos[number - 1] = logo.flatMap { $0.path.isEmpty ? nil : relative($0) } ?? none
            while logos.last?.path.isEmpty == true { logos.removeLast() }
            var document = self
            document.concert?.logos = logos
            return .success(unchanged(document, file: url))
        }
    }

    public func save(_ file: URL) throws {
        if let concert, file == url { return try ShowLoader.save(concert, to: file) }
        guard let movie = movies[file] else { throw ShowError.fileMissing(file) }
        try ShowLoader.save(movie, to: file)
    }

    // --- Editing ---

    private func insert(_ new: [Item], at place: Place) -> Result<EditResult, EditRefusal> {
        guard !new.isEmpty, var items = items(in: place.file), (0...items.count).contains(place.index) else {
            return .failure(.noSuchItem)
        }
        let concertLevel = isConcert(place.file)
        for item in new {
            switch item {
            case .clip where concertLevel: return .failure(.clipInConcert)
            case .movie where !concertLevel: return .failure(.movieInMovie)
            case .movie(let ref) where movies[resolve(ref)] == nil: return .failure(.noSuchItem)
            default: continue
            }
        }
        var order = oldOrder(items.count)
        items.insert(contentsOf: new, at: place.index)
        order.insert(contentsOf: [Int?](repeating: nil, count: new.count), at: place.index)
        return restructure(
            place.file, items, order, touched: Place(file: place.file, index: place.index + new.count - 1))
    }

    // order[new index] = the old index of the item now there, nil for an inserted one.
    private func restructure(_ file: URL, _ items: [Item], _ order: [Int?], touched: Place?) -> Result<
        EditResult, EditRefusal
    > {
        var document = self
        document.setItems(items, in: file)
        let moved = Dictionary(
            order.enumerated().compactMap { new, old in old.map { ($0, new) } }, uniquingKeysWith: { first, _ in first }
        )
        let lookup = Dictionary(
            document.origins.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let indexMap = origins.map { old -> Int? in
            var origin = old
            if isConcert(file), let index = origin.concert {
                guard let new = moved[index] else { return nil }
                origin.concert = new
            }
            if origin.movie == file, let index = origin.item {
                guard let new = moved[index] else { return nil }
                origin.item = new
            }
            return lookup[origin]
        }
        return .success(EditResult(document: document, indexMap: indexMap, changed: [file], touched: touched))
    }

    private func modify(_ place: Place, to item: Item) -> Result<EditResult, EditRefusal> {
        guard var items = items(in: place.file), items.indices.contains(place.index) else {
            return .failure(.noSuchItem)
        }
        items[place.index] = item
        var document = self
        document.setItems(items, in: place.file)
        var result = unchanged(document, file: place.file)
        result.touched = place
        return .success(result)
    }

    private func modifyClip(_ place: Place, _ change: (inout Clip) -> Void) -> Result<EditResult, EditRefusal> {
        guard case .clip(var clip)? = item(at: place) else { return .failure(.noSuchItem) }
        change(&clip)
        return modify(place, to: .clip(clip))
    }

    private func modifyBreak(_ place: Place, _ change: (inout BreakItem) -> Void) -> Result<EditResult, EditRefusal> {
        guard case .breakScreen(var item)? = item(at: place) else { return .failure(.noSuchItem) }
        change(&item)
        return modify(place, to: .breakScreen(item))
    }

    // Same cues in the same places: every cue keeps its index.
    private func unchanged(_ document: ShowDocument, file: URL) -> EditResult {
        EditResult(document: document, indexMap: cues.indices.map { $0 }, changed: [file], touched: nil)
    }

    private func oldOrder(_ count: Int) -> [Int?] {
        (0..<count).map { $0 }
    }

    private func relative(_ logo: Logo) -> Logo {
        let path = ShowLoader.relativePath(to: ShowLoader.resolve(logo.path, relativeTo: url), from: url)
        return if case .loop = logo { .loop(path) } else { .image(path) }
    }

    private static func text(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // --- Structure ---

    private func isConcert(_ file: URL) -> Bool {
        concert != nil && file == url
    }

    private func items(in file: URL) -> [Item]? {
        isConcert(file) ? concert?.items : movies[file]?.items
    }

    private func end(of file: URL) -> Place {
        Place(file: file, index: items(in: file)?.count ?? 0)
    }

    private func resolve(_ ref: MovieRef) -> URL {
        ShowLoader.resolve(ref.file, relativeTo: url)
    }

    private func movieURL(_ item: Item) -> URL? {
        if case .movie(let ref) = item { resolve(ref) } else { nil }
    }

    private mutating func setItems(_ items: [Item], in file: URL) {
        if isConcert(file) { concert?.items = items } else { movies[file]?.items = items }
        rebuild()
    }

    private mutating func rebuild() {
        var cues: [Cue] = []
        var rows: [Row] = []
        var origins: [Origin] = []
        func add(_ item: Item, movieIndex: Int?, base: URL, place: Place, origin: Origin) {
            for cue in ShowLoader.cue(for: item, movieIndex: movieIndex, base: base) {
                rows.append(Row(kind: .cue(cues.count), place: place, movie: origin.movie))
                origins.append(origin)
                cues.append(cue)
            }
        }
        func expand(_ file: URL, title: String, movieIndex: Int, concertIndex: Int?) {
            let header = concertIndex.map { Place(file: url, index: $0) }
            rows.append(Row(kind: .movie(movieIndex, title: movies[file]?.title ?? title), place: header, movie: file))
            for (index, item) in (movies[file]?.items ?? []).enumerated() {
                let origin = Origin(concert: concertIndex, movie: file, item: index)
                add(item, movieIndex: movieIndex, base: file, place: Place(file: file, index: index), origin: origin)
            }
        }
        if let concert {
            var movieIndex = 0
            for (index, item) in concert.items.enumerated() {
                if case .movie(let ref) = item {
                    expand(resolve(ref), title: ref.file, movieIndex: movieIndex, concertIndex: index)
                    movieIndex += 1
                } else {
                    add(
                        item, movieIndex: nil, base: url, place: Place(file: url, index: index),
                        origin: Origin(concert: index))
                }
            }
        } else {
            expand(url, title: url.lastPathComponent, movieIndex: 0, concertIndex: nil)
        }
        self.cues = cues
        self.rows = rows
        self.origins = origins
    }
}

// Where a flattened cue comes from: its concert entry and, inside a movie, the movie item.
private struct Origin: Hashable, Sendable {
    var concert: Int?
    var movie: URL?
    var item: Int?
}
