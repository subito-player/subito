import Foundation
import Testing

@testable import CueCore

@Suite struct PathTests {
    let file = URL(fileURLWithPath: "/shows/gala/gala.concert.json")

    @Test func relativePathsResolveAgainstTheFilesDirectory() {
        #expect(ShowLoader.resolve("showman.movie.json", relativeTo: file).path == "/shows/gala/showman.movie.json")
        #expect(ShowLoader.resolve("clips/01_x.mp4", relativeTo: file).path == "/shows/gala/clips/01_x.mp4")
    }

    @Test func absolutePathsStayAbsolute() {
        #expect(ShowLoader.resolve("/media/01_x.mp4", relativeTo: file).path == "/media/01_x.mp4")
    }
}

@Suite struct FlattenTests {
    @Test func concertExpandsEachMovieInPlace() throws {
        try withTempDir { dir in
            let clipA1 = Clip(file: "clips/01_x.mp4")
            let clipA2 = Clip(file: "clips/02_y.mp4")
            let clipB = Clip(file: "03_z.mp4")
            let breakItem = BreakItem(minutes: 20, countdown: true)
            try ShowLoader.save(
                Movie(title: "A", items: [.clip(clipA1), .black, .clip(clipA2)]),
                to: dir.appendingPathComponent("movies/a.movie.json").creatingParent())
            try ShowLoader.save(
                Movie(title: "B", items: [.clip(clipB)]), to: dir.appendingPathComponent("b.movie.json"))
            let concertURL = dir.appendingPathComponent("gala.concert.json")
            try ShowLoader.save(
                Concert(
                    title: "Gala",
                    items: [
                        .black,
                        .movie(MovieRef(file: "movies/a.movie.json")),
                        .breakScreen(breakItem),
                        .movie(MovieRef(file: "b.movie.json")),
                        .logo(LogoItem(logo: 1)),
                    ]),
                to: concertURL)

            let cues = ShowLoader.flatten(try ShowLoader.loadConcert(at: concertURL))

            func file(_ path: String) -> URL { URL(fileURLWithPath: dir.path + "/" + path) }
            #expect(
                cues == [
                    Cue(kind: .black, movieIndex: nil),
                    Cue(kind: .clip(clipA1, file("movies/clips/01_x.mp4")), movieIndex: 0),
                    Cue(kind: .black, movieIndex: 0),
                    Cue(kind: .clip(clipA2, file("movies/clips/02_y.mp4")), movieIndex: 0),
                    Cue(kind: .breakScreen(breakItem), movieIndex: nil),
                    Cue(kind: .clip(clipB, file("03_z.mp4")), movieIndex: 1),
                    Cue(kind: .logo(1), movieIndex: nil),
                ])
        }
    }

    @Test func singleMovieIsMovieZero() {
        let clip = Clip(file: "01_x.mp4")
        let cues = ShowLoader.flatten(
            movie: Movie(title: "A", items: [.clip(clip), .black]),
            at: URL(fileURLWithPath: "/shows/a.movie.json"))
        #expect(
            cues == [
                Cue(kind: .clip(clip, URL(fileURLWithPath: "/shows/01_x.mp4")), movieIndex: 0),
                Cue(kind: .black, movieIndex: 0),
            ])
    }
}

@Suite struct ValidationTests {
    @Test func missingFile() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("gone.movie.json")
            #expect(throws: ShowError.fileMissing(url)) { try ShowLoader.loadMovie(at: url) }
            #expect(throws: ShowError.fileMissing(url)) { try ShowLoader.loadConcert(at: url) }
            #expect(ShowError.fileMissing(url).description.contains(url.path))
        }
    }

    @Test(arguments: [
        ("{ not json", "JSON"),
        (#"{ "format": 1 }"#, "title"),
        (#"{ "format": 1, "title": "T", "items": [ { "type": "banana" } ] }"#, "banana"),
    ])
    func invalidJSONCarriesTheUnderlyingMessage(json: String, fragment: String) throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("bad.movie.json")
            try write(json, to: url)
            #expect {
                try ShowLoader.loadMovie(at: url)
            } throws: { error in
                guard case ShowError.invalidJSON(let file, let message) = error else { return false }
                return file == url && message.contains(fragment) && "\(error)".contains("bad.movie.json")
            }
        }
    }

    @Test func newerFormatIsRefusedEvenWhenTheBodyIsUnreadable() throws {
        try withTempDir { dir in
            let json = #"{ "format": 2, "title": "T", "items": [ { "type": "hologram" } ] }"#
            let movie = dir.appendingPathComponent("new.movie.json")
            let concert = dir.appendingPathComponent("new.concert.json")
            try write(json, to: movie)
            try write(json, to: concert)
            #expect(throws: ShowError.unsupportedFormat(file: movie, format: 2)) { try ShowLoader.loadMovie(at: movie) }
            #expect(throws: ShowError.unsupportedFormat(file: concert, format: 2)) {
                try ShowLoader.loadConcert(at: concert)
            }
            #expect(ShowError.unsupportedFormat(file: movie, format: 2).description.contains("format 2"))
        }
    }

    @Test(arguments: [
        #"{ "type": "break", "minutes": 1 }"#,
        #"{ "type": "logo", "logo": 1 }"#,
    ])
    func movieMayHoldBreakAndLogoItems(item: String) throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.movie.json")
            try write(#"{ "format": 1, "title": "T", "items": [ { "type": "black" }, \#(item) ] }"#, to: url)
            #expect(try ShowLoader.loadMovie(at: url).items.count == 2)
        }
    }

    @Test func movieMayNotHoldAMovie() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.movie.json")
            try write(
                #"{ "format": 1, "title": "T", "items": [ { "type": "movie", "file": "b.movie.json" } ] }"#, to: url)
            #expect(throws: ShowError.movieContainsMovie(file: url)) { try ShowLoader.loadMovie(at: url) }
            #expect(ShowError.movieContainsMovie(file: url).description.contains("a.movie.json"))
        }
    }

    @Test func concertMayNotHoldClips() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.concert.json")
            try write(
                #"{ "format": 1, "title": "T", "logos": [], "items": [ { "type": "clip", "file": "01_x.mp4" } ] }"#,
                to: url)
            #expect(throws: ShowError.concertHasClip(file: url)) { try ShowLoader.loadConcert(at: url) }
            #expect(ShowError.concertHasClip(file: url).description.contains("a.concert.json"))
        }
    }

    @Test func referencedMovieMustExist() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.concert.json")
            try ShowLoader.save(
                Concert(title: "T", items: [.movie(MovieRef(file: "gone.movie.json"))]), to: url)
            let expected = ShowError.movieFileMissing(concert: url, path: "gone.movie.json")
            #expect(throws: expected) { try ShowLoader.loadConcert(at: url) }
            #expect(expected.description.contains("gone.movie.json"))
        }
    }
}

@Suite struct FolderTests {
    @Test func folderBecomesAMovieOrderedByNumberThenName() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("My Show")
            let names = [
                "10_x.mp4", "02_y.mov", "01_b.mp4", "01_a.M4V", "notes.txt", "cover.mp4", "03_z.avi", ".DS_Store",
            ]
            for name in names { try write("", to: folder.appendingPathComponent(name)) }
            try write("", to: folder.appendingPathComponent("04_nested/01_inner.mp4"))
            let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

            let movie = try ShowLoader.movie(fromFolder: folder)

            let expected = ["01_a.M4V", "01_b.mp4", "02_y.mov", "03_z.avi", "10_x.mp4"].map {
                Item.clip(Clip(file: $0))
            }
            #expect(movie == Movie(title: "My Show", items: expected))
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == before)
        }
    }
}

@Suite struct ConvertibleFolderTests {
    @Test func clipsThatNeedConvertingAreListedUntilTheirMP4Exists() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("Old")
            for name in ["01_a.mkv", "02_b.webm", "02_b.mp4", "03_c.avi", "04_d.srt"] {
                try write("", to: folder.appendingPathComponent(name))
            }
            let movie = try ShowLoader.movie(fromFolder: folder)
            #expect(movie.items == ["01_a.mkv", "02_b.mp4", "03_c.avi"].map { Item.clip(Clip(file: $0)) })
        }
    }
}

@Suite struct ImportFolderTests {
    @Test func firstImportWritesTheMovieFileInsideTheFolder() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("My Show")
            for name in ["02_b.mp4", "01_a.mp4", "notes.txt"] { try write("", to: folder.appendingPathComponent(name)) }

            let url = try ShowLoader.importFolder(folder)

            #expect(url.deletingLastPathComponent().path == folder.path)
            #expect(url.lastPathComponent == "My Show.movie.json")
            let movie = try ShowLoader.loadMovie(at: url)
            #expect(movie.title == "My Show")
            #expect(movie.items == [.clip(Clip(file: "01_a.mp4")), .clip(Clip(file: "02_b.mp4"))])
            let cues = ShowLoader.flatten(movie: movie, at: url)
            #expect(cues.first?.kind == .clip(Clip(file: "01_a.mp4"), URL(fileURLWithPath: folder.path + "/01_a.mp4")))
        }
    }

    @Test func secondImportKeepsOperatorEdits() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("My Show")
            try write("", to: folder.appendingPathComponent("01_a.mp4"))
            let url = try ShowLoader.importFolder(folder)
            var edited = try ShowLoader.loadMovie(at: url)
            edited.title = "Edited"
            try ShowLoader.save(edited, to: url)
            try write("", to: folder.appendingPathComponent("02_b.mp4"))

            #expect(try ShowLoader.importFolder(folder) == url)
            #expect(try ShowLoader.loadMovie(at: url) == edited)
        }
    }
}

extension URL {
    fileprivate func creatingParent() throws -> URL {
        try FileManager.default.createDirectory(at: deletingLastPathComponent(), withIntermediateDirectories: true)
        return self
    }
}
