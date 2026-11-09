import Foundation
import Testing

@testable import CueCore

private let concertURL = URL(fileURLWithPath: "/show/gala.concert.json")
private let movieA = URL(fileURLWithPath: "/show/a.movie.json")
private let movieB = URL(fileURLWithPath: "/show/b.movie.json")
private let clipX = Clip(file: "01_x.mp4")
private let clipY = Clip(file: "02_y.mp4")
private let clipZ = Clip(file: "03_z.mp4")
private let breakItem = BreakItem(minutes: 20, countdown: true)

private func place(_ file: URL, _ index: Int) -> Place {
    Place(file: file, index: index)
}

// Cues: 0 black, 1 x, 2 black, 3 y (movie A), 4 break, 5 z (movie B), 6 logo 1.
private func gala(twiceA: Bool = false) -> ShowDocument {
    var items: [Item] = [
        .black, .movie(MovieRef(file: "a.movie.json")), .breakScreen(breakItem),
        .movie(MovieRef(file: "b.movie.json")), .logo(LogoItem(logo: 1)),
    ]
    if twiceA { items.append(.movie(MovieRef(file: "a.movie.json"))) }
    return ShowDocument(
        LoadedConcert(
            concert: Concert(title: "Gala", logos: [.image("logos/o.png"), .loop("logos/e.mp4")], items: items),
            url: concertURL,
            movies: [
                ShowLoader.resolve("a.movie.json", relativeTo: concertURL): Movie(
                    title: "A", items: [.clip(clipX), .black, .clip(clipY)]),
                ShowLoader.resolve("b.movie.json", relativeTo: concertURL): Movie(title: "B", items: [.clip(clipZ)]),
            ]))
}

private func single() -> ShowDocument {
    ShowDocument(movie: Movie(title: "A", items: [.clip(clipX), .black, .clip(clipY)]), at: movieA)
}

extension Result where Success == EditResult, Failure == EditRefusal {
    fileprivate var edited: EditResult {
        get throws { try get() }
    }

    fileprivate var refusal: EditRefusal? {
        if case .failure(let refusal) = self { refusal } else { nil }
    }
}

extension ShowDocument {
    fileprivate func items(_ file: URL) -> [Item] {
        file == url && concert != nil ? concert?.items ?? [] : movies[file]?.items ?? []
    }
}

@Suite struct DocumentStructureTests {
    @Test func cuesMatchTheLoaderFlatteningAndRowsAddMovieHeaders() {
        let document = gala()
        let loaded = LoadedConcert(concert: document.concert!, url: concertURL, movies: document.movies)
        #expect(document.cues == ShowLoader.flatten(loaded))
        #expect(
            document.rows == [
                Row(kind: .cue(0), place: place(concertURL, 0), movie: nil),
                Row(kind: .movie(0, title: "A"), place: place(concertURL, 1), movie: movieA),
                Row(kind: .cue(1), place: place(movieA, 0), movie: movieA),
                Row(kind: .cue(2), place: place(movieA, 1), movie: movieA),
                Row(kind: .cue(3), place: place(movieA, 2), movie: movieA),
                Row(kind: .cue(4), place: place(concertURL, 2), movie: nil),
                Row(kind: .movie(1, title: "B"), place: place(concertURL, 3), movie: movieB),
                Row(kind: .cue(5), place: place(movieB, 0), movie: movieB),
                Row(kind: .cue(6), place: place(concertURL, 4), movie: nil),
            ])
        #expect(document.title == "Gala")
        #expect(document.logos.map(\.path) == ["/show/logos/o.png", "/show/logos/e.mp4"])
    }

    @Test func singleMovieHeaderBelongsToNoFile() {
        let document = single()
        #expect(document.rows.first == Row(kind: .movie(0, title: "A"), place: nil, movie: movieA))
        #expect(document.rows.dropFirst().map(\.place) == [place(movieA, 0), place(movieA, 1), place(movieA, 2)])
        #expect(document.cues == ShowLoader.flatten(movie: document.movies[movieA]!, at: movieA))
        #expect(document.title == "A")
        #expect(document.logos.isEmpty)
    }

    @Test func emptyMovieStillHasItsHeader() {
        let document = ShowDocument(movie: Movie(title: "New"), at: movieA)
        #expect(document.cues.isEmpty)
        #expect(document.rows == [Row(kind: .movie(0, title: "New"), place: nil, movie: movieA)])
    }
}

@Suite struct InsertTests {
    @Test func itemIntoAMovieShiftsTheCuesAfterIt() throws {
        let result = try gala().apply(.insert(.black, at: place(movieA, 1)), live: nil).edited
        #expect(result.document.items(movieA) == [.clip(clipX), .black, .black, .clip(clipY)])
        #expect(result.indexMap == [0, 1, 3, 4, 5, 6, 7])
        #expect(result.changed == [movieA])
        #expect(result.touched == place(movieA, 1))
    }

    @Test func itemIntoTheConcertShiftsEverythingAfterIt() throws {
        let result = try gala().apply(.insert(.logo(LogoItem(logo: 2)), at: place(concertURL, 0)), live: nil).edited
        #expect(result.document.items(concertURL).first == .logo(LogoItem(logo: 2)))
        #expect(result.document.cues.first == Cue(kind: .logo(2), movieIndex: nil))
        #expect(result.indexMap == [1, 2, 3, 4, 5, 6, 7])
        #expect(result.changed == [concertURL])
    }

    @Test func aMovieUsedTwiceGetsTheItemInBothPlaces() throws {
        let result = try gala(twiceA: true).apply(.insert(.black, at: place(movieA, 3)), live: nil).edited
        // Second copy of A starts at old cue 7.
        #expect(result.indexMap == [0, 1, 2, 3, 5, 6, 7, 8, 9, 10])
        #expect(result.document.cues.count == 12)
        #expect(result.document.cues[4] == Cue(kind: .black, movieIndex: 0))
        #expect(result.document.cues[11] == Cue(kind: .black, movieIndex: 2))
        #expect(result.changed == [movieA])
    }

    @Test func clipsGetPathsRelativeToTheirMovie() throws {
        let files = [
            URL(fileURLWithPath: "/show/clips/04_w.mp4"), URL(fileURLWithPath: "/media/05_v.mp4"),
        ]
        let result = try gala().apply(.insertClips(files, at: place(movieB, 1)), live: nil).edited
        #expect(
            result.document.items(movieB) == [
                .clip(clipZ), .clip(Clip(file: "clips/04_w.mp4")), .clip(Clip(file: "/media/05_v.mp4")),
            ])
        #expect(result.document.cues[6] == Cue(kind: .clip(Clip(file: "clips/04_w.mp4"), files[0]), movieIndex: 1))
        #expect(result.indexMap == [0, 1, 2, 3, 4, 5, 8])
        #expect(result.touched == place(movieB, 2))
    }

    @Test func movieIntoTheConcertIsReferencedRelativelyAndExpanded() throws {
        let file = URL(fileURLWithPath: "/show/sub/c.movie.json")
        let movie = Movie(title: "C", items: [.clip(Clip(file: "07_c.mp4"))])
        let result = try gala().apply(.insertMovie(movie, file, at: 2), live: nil).edited
        #expect(result.document.items(concertURL)[2] == .movie(MovieRef(file: "sub/c.movie.json")))
        #expect(result.document.rows[5] == Row(kind: .movie(1, title: "C"), place: place(concertURL, 2), movie: file))
        #expect(
            result.document.cues[4]
                == Cue(kind: .clip(Clip(file: "07_c.mp4"), URL(fileURLWithPath: "/show/sub/07_c.mp4")), movieIndex: 1))
        #expect(
            result.document.cues[6] == Cue(kind: .clip(clipZ, URL(fileURLWithPath: "/show/03_z.mp4")), movieIndex: 2))
        #expect(result.indexMap == [0, 1, 2, 3, 5, 6, 7])
        #expect(result.changed == [concertURL])
        #expect(result.touched == place(concertURL, 2))
    }

    @Test func aMovieAlreadyInTheShowKeepsItsInMemoryItems() throws {
        let stale = Movie(title: "A from disk", items: [])
        let result = try gala().apply(.insertMovie(stale, movieA, at: 5), live: nil).edited
        #expect(result.document.movies[movieA]?.title == "A")
        #expect(result.document.cues.count == 10)
    }

    @Test func refusedWhereTheFileTypeForbidsIt() {
        let document = gala()
        let clip = Item.clip(clipX)
        #expect(document.apply(.insert(clip, at: place(concertURL, 0)), live: nil).refusal == .clipInConcert)
        #expect(
            document.apply(.insertClips([URL(fileURLWithPath: "/show/x.mp4")], at: place(concertURL, 0)), live: nil)
                .refusal == .clipInConcert)
        let movieItem = Item.movie(MovieRef(file: "b.movie.json"))
        #expect(document.apply(.insert(movieItem, at: place(movieA, 0)), live: nil).refusal == .movieInMovie)
        #expect(single().apply(.insertMovie(Movie(title: "C"), movieB, at: 0), live: nil).refusal == .movieInMovie)
        #expect(
            document.apply(.insert(.movie(MovieRef(file: "unknown.movie.json")), at: place(concertURL, 0)), live: nil)
                .refusal == .noSuchItem)
    }

    @Test func outOfRangeAndEmptyInsertsAreRefused() {
        let document = gala()
        #expect(document.apply(.insert(.black, at: place(movieA, 4)), live: nil).refusal == .noSuchItem)
        #expect(document.apply(.insert(.black, at: place(movieA, -1)), live: nil).refusal == .noSuchItem)
        #expect(document.apply(.insertClips([], at: place(movieA, 0)), live: nil).refusal == .noSuchItem)
        let unknown = URL(fileURLWithPath: "/show/unknown.movie.json")
        #expect(document.apply(.insert(.black, at: place(unknown, 0)), live: nil).refusal == .noSuchItem)
    }
}

@Suite struct DeleteAndMoveTests {
    @Test func deletingAMovieItemDropsItsCue() throws {
        let result = try gala().apply(.delete(place(movieA, 1)), live: 5).edited
        #expect(result.document.items(movieA) == [.clip(clipX), .clip(clipY)])
        #expect(result.indexMap == [0, 1, nil, 2, 3, 4, 5])
        #expect(result.changed == [movieA])
        #expect(result.touched == nil)
    }

    @Test func deletingAMovieFromTheConcertDropsAllItsCues() throws {
        let result = try gala().apply(.delete(place(concertURL, 1)), live: 6).edited
        #expect(result.document.cues.count == 4)
        #expect(result.indexMap == [0, nil, nil, nil, 1, 2, 3])
        #expect(result.document.rows[2] == Row(kind: .movie(0, title: "B"), place: place(concertURL, 2), movie: movieB))
        #expect(result.changed == [concertURL])
    }

    @Test func movingWithinAMovieReordersOnlyItsCues() throws {
        let result = try gala().apply(.move(place(movieA, 0), to: 2), live: 6).edited
        #expect(result.document.items(movieA) == [.black, .clip(clipY), .clip(clipX)])
        #expect(result.indexMap == [0, 3, 1, 2, 4, 5, 6])
        #expect(result.touched == place(movieA, 2))
        let back = try result.document.apply(.move(place(movieA, 2), to: 0), live: nil).edited
        #expect(back.document == gala())
    }

    @Test func movingAMovieInTheConcertMovesItsWholeBlock() throws {
        let result = try gala().apply(.move(place(concertURL, 3), to: 0), live: 4).edited
        #expect(result.document.items(concertURL).first == .movie(MovieRef(file: "b.movie.json")))
        #expect(result.indexMap == [1, 2, 3, 4, 5, 0, 6])
        #expect(
            result.document.cues[0] == Cue(kind: .clip(clipZ, URL(fileURLWithPath: "/show/03_z.mp4")), movieIndex: 0))
        #expect(
            result.document.cues[2] == Cue(kind: .clip(clipX, URL(fileURLWithPath: "/show/01_x.mp4")), movieIndex: 1))
    }

    @Test func theLiveItemCannotBeDeletedOrMoved() {
        let document = gala()
        #expect(document.apply(.delete(place(movieA, 2)), live: 3).refusal == .liveItemLocked)
        #expect(document.apply(.move(place(movieA, 2), to: 0), live: 3).refusal == .liveItemLocked)
        #expect(document.apply(.delete(place(concertURL, 2)), live: 4).refusal == .liveItemLocked)
        #expect(document.apply(.move(place(concertURL, 4), to: 0), live: 6).refusal == .liveItemLocked)
    }

    @Test func theMovieHoldingTheLiveCueCannotBeDeletedOrMoved() {
        let document = gala()
        #expect(document.isLocked(place(concertURL, 1), live: 3))
        #expect(!document.isLocked(place(concertURL, 3), live: 3))
        #expect(document.apply(.delete(place(concertURL, 1)), live: 3).refusal == .liveItemLocked)
        #expect(document.apply(.move(place(concertURL, 1), to: 4), live: 3).refusal == .liveItemLocked)
    }

    @Test func aMovieItemUsedTwiceIsLockedInBothCopiesWhenOneIsLive() {
        let document = gala(twiceA: true)
        #expect(document.isLocked(place(movieA, 0), live: 7))
        #expect(document.isLocked(place(concertURL, 5), live: 7))
        #expect(!document.isLocked(place(concertURL, 1), live: 7))
        #expect(document.apply(.delete(place(movieA, 0)), live: 7).refusal == .liveItemLocked)
    }

    @Test func otherItemsMoveAroundTheLiveOne() throws {
        let result = try gala().apply(.move(place(movieA, 0), to: 2), live: 3).edited
        #expect(result.indexMap[3] == 2)
        let deleted = try gala().apply(.delete(place(concertURL, 0)), live: 3).edited
        #expect(deleted.indexMap[3] == 2)
        #expect(!gala().isLocked(place(movieA, 0), live: nil))
        #expect(!gala().isLocked(place(movieA, 0), live: 99))
    }

    @Test func outOfRangeIsRefused() {
        let document = gala()
        #expect(document.apply(.delete(place(movieB, 1)), live: nil).refusal == .noSuchItem)
        #expect(document.apply(.move(place(movieB, 0), to: 1), live: nil).refusal == .noSuchItem)
        #expect(document.apply(.move(place(movieB, 1), to: 0), live: nil).refusal == .noSuchItem)
    }
}

@Suite struct ChangeTests {
    @Test func clipTitleAndTimesKeepEveryCueInPlace() throws {
        let document = gala()
        let renamed = try document.apply(.renameClip(place(movieA, 0), "  Opening  "), live: 1).edited
        #expect(renamed.document.items(movieA)[0] == .clip(Clip(file: "01_x.mp4", title: "Opening")))
        #expect(renamed.indexMap == [0, 1, 2, 3, 4, 5, 6])
        #expect(renamed.changed == [movieA])
        #expect(renamed.touched == place(movieA, 0))
        let cleared = try renamed.document.apply(.renameClip(place(movieA, 0), " "), live: nil).edited
        #expect(cleared.document.items(movieA)[0] == .clip(clipX))

        let timed = try document.apply(.setClipTimes(place(movieA, 2), plannedEndS: 212.5, tailS: 60), live: nil)
            .edited
        #expect(timed.document.items(movieA)[2] == .clip(Clip(file: "02_y.mp4", plannedEndS: 212.5, tailS: 60)))
        let untimed = try timed.document.apply(.setClipTimes(place(movieA, 2), plannedEndS: nil, tailS: nil), live: nil)
            .edited
        #expect(untimed.document.items(movieA)[2] == .clip(clipY))
    }

    @Test func breakTextAndFields() throws {
        let document = gala()
        let texted = try document.apply(.setBreakText(place(concertURL, 2), "Szünet"), live: nil).edited
        #expect(
            texted.document.cues[4]
                == Cue(kind: .breakScreen(BreakItem(minutes: 20, countdown: true, text: "Szünet")), movieIndex: nil))
        #expect(texted.changed == [concertURL])
        let cleared = try texted.document.apply(.setBreakText(place(concertURL, 2), ""), live: nil).edited
        #expect(cleared.document.items(concertURL)[2] == .breakScreen(breakItem))
        let set = try document.apply(.setBreak(place(concertURL, 2), minutes: 15, countdown: false), live: 4).edited
        #expect(set.document.items(concertURL)[2] == .breakScreen(BreakItem(minutes: 15, countdown: false)))
        #expect(set.indexMap == [0, 1, 2, 3, 4, 5, 6])
    }

    @Test func logoNumber() throws {
        let result = try gala().apply(.setLogo(place(concertURL, 4), 2), live: nil).edited
        #expect(result.document.cues[6] == Cue(kind: .logo(2), movieIndex: nil))
    }

    @Test func movieAndConcertTitles() throws {
        let movie = try gala().apply(.renameMovie(movieB, " Showman "), live: nil).edited
        #expect(movie.document.movies[movieB]?.title == "Showman")
        #expect(movie.document.rows[6].kind == .movie(1, title: "Showman"))
        #expect(movie.changed == [movieB])
        let concert = try gala().apply(.renameConcert("Spring Gala"), live: nil).edited
        #expect(concert.document.title == "Spring Gala")
        #expect(concert.changed == [concertURL])
        let alone = try single().apply(.renameMovie(movieA, "Solo"), live: nil).edited
        #expect(alone.document.title == "Solo")
        #expect(alone.document.rows[0].kind == .movie(0, title: "Solo"))
    }

    @Test func replacedClipFileSwapsOnlyTheNameAndEveryCueKeepsItsPlace() throws {
        let converted = URL(fileURLWithPath: "/show/01_x.mp4")
        let mkv = try single().apply(
            .replaceClipFile(place(movieA, 0), URL(fileURLWithPath: "/show/01_x.mkv")), live: 0
        )
        .edited
        let result = try mkv.document.apply(.replaceClipFile(place(movieA, 0), converted), live: 0).edited
        #expect(result.document.items(movieA)[0] == .clip(clipX))
        #expect(result.document.cues[0].kind == .clip(clipX, converted))
        #expect(result.indexMap == [0, 1, 2])
        #expect(result.changed == [movieA])
        #expect(result.touched == place(movieA, 0))
    }

    @Test func replacedClipFileKeepsTheFolderAsWrittenRelativeOrAbsolute() throws {
        let document = ShowDocument(
            movie: Movie(
                title: "A",
                items: [.clip(Clip(file: "../media/01_x.mkv")), .clip(Clip(file: "/Volumes/Stage/02_y.avi"))]),
            at: movieA)
        let up = try document.apply(
            .replaceClipFile(place(movieA, 0), URL(fileURLWithPath: "/media/01_x.mp4")), live: nil
        )
        .edited
        #expect(up.document.items(movieA)[0] == .clip(Clip(file: "../media/01_x.mp4")))
        #expect(
            up.document.cues[0].kind == .clip(Clip(file: "../media/01_x.mp4"), URL(fileURLWithPath: "/media/01_x.mp4")))
        let absolute = try up.document.apply(
            .replaceClipFile(place(movieA, 1), URL(fileURLWithPath: "/Volumes/Stage/02_y.mp4")), live: nil
        ).edited
        #expect(absolute.document.items(movieA)[1] == .clip(Clip(file: "/Volumes/Stage/02_y.mp4")))
    }

    @Test func replacedClipFileKeepsTheTitleTheListShowed() throws {
        let renamed = try single().apply(
            .replaceClipFile(place(movieA, 0), URL(fileURLWithPath: "/show/01_x (converted).mp4")), live: nil
        ).edited
        #expect(renamed.document.items(movieA)[0] == .clip(Clip(file: "01_x (converted).mp4", title: "X")))
        let titled = try renamed.document.apply(.renameClip(place(movieA, 0), "Opening"), live: nil).edited
        let again = try titled.document.apply(
            .replaceClipFile(place(movieA, 0), URL(fileURLWithPath: "/show/01_x (converted 2).mp4")), live: nil
        ).edited
        #expect(again.document.items(movieA)[0] == .clip(Clip(file: "01_x (converted 2).mp4", title: "Opening")))
    }

    @Test func replacedClipFileReachesEveryCueOfAMovieUsedTwice() throws {
        let converted = URL(fileURLWithPath: "/show/01_x.mp4")
        let result = try gala(twiceA: true).apply(.replaceClipFile(place(movieA, 0), converted), live: nil).edited
        #expect(result.document.cues[1].kind == .clip(clipX, converted))
        #expect(result.document.cues[7].kind == .clip(clipX, converted))
        #expect(result.indexMap == Array(0..<10))
    }

    @Test func wrongKindOrMissingTargetIsRefused() {
        let document = gala()
        #expect(document.apply(.renameClip(place(movieA, 1), "x"), live: nil).refusal == .noSuchItem)
        #expect(
            document.apply(.setClipTimes(place(movieA, 9), plannedEndS: 1, tailS: 1), live: nil).refusal == .noSuchItem)
        #expect(document.apply(.setBreakText(place(movieA, 0), "x"), live: nil).refusal == .noSuchItem)
        #expect(
            document.apply(.setBreak(place(concertURL, 0), minutes: 1, countdown: true), live: nil).refusal
                == .noSuchItem)
        #expect(document.apply(.setLogo(place(concertURL, 0), 2), live: nil).refusal == .noSuchItem)
        #expect(
            document.apply(.replaceClipFile(place(movieA, 1), URL(fileURLWithPath: "/show/x.mp4")), live: nil).refusal
                == .noSuchItem)
        #expect(document.apply(.renameMovie(concertURL, "x"), live: nil).refusal == .noSuchItem)
        #expect(single().apply(.renameConcert("x"), live: nil).refusal == .noSuchItem)
    }
}

@Suite struct InsertionPlaceTests {
    @Test func itemsGoAfterTheSelectionOrAtTheEndOfTheShow() {
        let document = gala()
        #expect(document.insertionPlace(for: .item, selected: place(movieA, 1)) == place(movieA, 2))
        #expect(document.insertionPlace(for: .item, selected: place(concertURL, 1)) == place(concertURL, 2))
        #expect(document.insertionPlace(for: .item, selected: nil) == place(concertURL, 5))
        #expect(document.insertionPlace(for: .item, selected: place(movieA, 7)) == place(concertURL, 5))
        #expect(single().insertionPlace(for: .item, selected: nil) == place(movieA, 3))
    }

    @Test func clipsGoIntoTheSelectedMovieOrTheOnlyOne() {
        let document = gala()
        #expect(document.insertionPlace(for: .clip, selected: place(movieA, 0)) == place(movieA, 1))
        #expect(document.insertionPlace(for: .clip, selected: place(concertURL, 3)) == place(movieB, 1))
        #expect(document.insertionPlace(for: .clip, selected: place(concertURL, 0)) == nil)
        #expect(document.insertionPlace(for: .clip, selected: nil) == nil)
        #expect(single().insertionPlace(for: .clip, selected: nil) == place(movieA, 3))
        let onlyB = try? document.apply(.delete(place(concertURL, 1)), live: nil).get().document
        #expect(onlyB?.insertionPlace(for: .clip, selected: place(concertURL, 0)) == place(movieB, 1))
    }

    @Test func moviesGoIntoTheConcertAfterTheSelection() {
        let document = gala()
        #expect(document.insertionPlace(for: .movie, selected: place(concertURL, 2)) == place(concertURL, 3))
        #expect(document.insertionPlace(for: .movie, selected: place(movieB, 0)) == place(concertURL, 4))
        #expect(document.insertionPlace(for: .movie, selected: nil) == place(concertURL, 5))
        #expect(single().insertionPlace(for: .movie, selected: nil) == nil)
    }
}

@Suite struct DocumentFileTests {
    @Test func editsSaveToTheirFileAndLoadBack() throws {
        try withTempDir { dir in
            let movieURL = dir.appendingPathComponent("a.movie.json")
            let concert = dir.appendingPathComponent("gala.concert.json")
            try ShowLoader.save(Movie(title: "A", items: [.clip(clipX)]), to: movieURL)
            try ShowLoader.save(Concert(title: "Gala", items: [.movie(MovieRef(file: "a.movie.json"))]), to: concert)
            let document = try ShowDocument.load(concert)
            let movieKey = try #require(document.rows.first?.movie)

            let inserted = try document.apply(.insert(.black, at: Place(file: movieKey, index: 1)), live: nil).edited
            for file in inserted.changed { try inserted.document.save(file) }
            let added = try inserted.document.apply(.insert(.black, at: Place(file: concert, index: 0)), live: nil)
                .edited
            for file in added.changed { try added.document.save(file) }

            #expect(try ShowDocument.load(concert) == added.document)
            #expect(throws: ShowError.self) { try document.save(dir.appendingPathComponent("other.movie.json")) }
        }
    }

    @Test func loadOpensConcertsMoviesAndFolders() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("showman")
            try write("", to: folder.appendingPathComponent("01_the_show.mp4"))
            let fromFolder = try ShowDocument.load(folder)
            #expect(fromFolder.url == ShowLoader.movieFile(inFolder: folder))
            #expect(fromFolder.concert == nil)
            #expect(fromFolder.cues.count == 1)
            #expect(try ShowDocument.load(fromFolder.url) == fromFolder)

            let concert = dir.appendingPathComponent("gala.concert.json")
            try ShowLoader.save(Concert(title: "Gala", items: [.black]), to: concert)
            #expect(try ShowDocument.load(concert).title == "Gala")
        }
    }

    @Test func loadReadOnlyReadsAFolderInMemoryAndWritesNothing() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("showman")
            for name in ["02_b.mp4", "01_a.mp4", "notes.txt"] { try write("", to: folder.appendingPathComponent(name)) }
            let before = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()

            let document = try ShowDocument.loadReadOnly(folder)

            #expect(document.url == ShowLoader.movieFile(inFolder: folder))
            #expect(document.title == "showman")
            #expect(
                document.cues.map(\.kind) == [
                    .clip(Clip(file: "01_a.mp4"), folder.appendingPathComponent("01_a.mp4")),
                    .clip(Clip(file: "02_b.mp4"), folder.appendingPathComponent("02_b.mp4")),
                ])
            #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted() == before)
        }
    }

    @Test func loadReadOnlyPrefersAFolderMovieFileAndLoadsFilesLikeLoad() throws {
        try withTempDir { dir in
            let folder = dir.appendingPathComponent("showman")
            try write("", to: folder.appendingPathComponent("01_a.mp4"))
            let file = ShowLoader.movieFile(inFolder: folder)
            try ShowLoader.save(Movie(title: "Edited", items: [.clip(Clip(file: "01_a.mp4")), .black]), to: file)
            let edited = try ShowDocument.loadReadOnly(folder)
            #expect(edited.title == "Edited")
            #expect(edited.cues.count == 2)
            #expect(edited == (try ShowDocument.load(folder)))

            let concert = dir.appendingPathComponent("gala.concert.json")
            try ShowLoader.save(Concert(title: "Gala", items: [.black]), to: concert)
            #expect(try ShowDocument.loadReadOnly(concert) == ShowDocument.load(concert))
            #expect(try ShowDocument.loadReadOnly(file) == ShowDocument.load(file))
        }
    }

    @Test func loadReadOnlyReportsAMissingShow() throws {
        try withTempDir { dir in
            let missing = dir.appendingPathComponent("gone.concert.json")
            #expect(throws: ShowError.fileMissing(missing)) { try ShowDocument.loadReadOnly(missing) }
        }
    }

    @Test func newConcertNamesItsFileAndNeverOverwrites() throws {
        try withTempDir { dir in
            for name in ["Gala", "Gala.json", "Gala.concert.json"] {
                let file = try ShowLoader.createConcert(at: dir.appendingPathComponent(name))
                #expect(file.lastPathComponent == "Gala.concert.json")
            }
            let file = dir.appendingPathComponent("Gala.concert.json")
            #expect(try ShowLoader.loadConcert(at: file).concert == Concert(title: "Gala"))
            try ShowLoader.save(Concert(title: "Gala", items: [.black]), to: file)
            _ = try ShowLoader.createConcert(at: file)
            #expect(try ShowLoader.loadConcert(at: file).concert.items == [.black])
        }
    }

    @Test func relativeOnlyInsideTheFilesOwnFolderTree() {
        let file = URL(fileURLWithPath: "/Users/op/shows/gala/gala.concert.json")
        func path(_ target: String) -> String {
            ShowLoader.relativePath(to: URL(fileURLWithPath: target), from: file)
        }
        #expect(path("/Users/op/shows/gala/a.movie.json") == "a.movie.json")
        #expect(path("/Users/op/shows/gala/clips/01_x.mp4") == "clips/01_x.mp4")
        #expect(path("/Users/op/shows/clips/01_x.mp4") == "/Users/op/shows/clips/01_x.mp4")
        #expect(path("/Users/op/Movies/01_x.mp4") == "/Users/op/Movies/01_x.mp4")
        #expect(path("/Volumes/USB/01_x.mp4") == "/Volumes/USB/01_x.mp4")
        #expect(
            ShowLoader.resolve(path("/Users/op/shows/gala/clips/01_x.mp4"), relativeTo: file).path
                == "/Users/op/shows/gala/clips/01_x.mp4")
    }

    @Test func symlinkedFoldersStillGiveRelativePaths() throws {
        let dir = URL(fileURLWithPath: "/tmp/cue-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let movie = dir.appendingPathComponent("a.movie.json")
        try write("{}", to: movie)
        try write("", to: dir.appendingPathComponent("clips/01_x.mp4"))
        let viaPrivate = URL(fileURLWithPath: "/private" + dir.path + "/clips/01_x.mp4")
        #expect(ShowLoader.relativePath(to: viaPrivate, from: movie) == "clips/01_x.mp4")
        let privateMovie = URL(fileURLWithPath: "/private" + movie.path)
        #expect(
            ShowLoader.relativePath(to: dir.appendingPathComponent("clips/01_x.mp4"), from: privateMovie)
                == "clips/01_x.mp4")
    }
}

@Suite struct ClockTests {
    @Test(arguments: [
        ("3:25", 205.0), ("0:45", 45), ("45", 45), ("212.5", 212.5), ("3:32,5", 212.5), (" 1:05 ", 65), ("10:00", 600),
    ])
    func parses(text: String, seconds: Double) {
        #expect(Clock.seconds(from: text) == seconds)
    }

    @Test(arguments: ["", "3:", ":30", "1:60", "-5", "1:-5", "a", "1:2:3", "nan", "inf"])
    func rejects(text: String) {
        #expect(Clock.seconds(from: text) == nil)
    }

    @Test func textRoundTripsToTheMillisecond() {
        #expect(Clock.text(205) == "3:25")
        #expect(Clock.text(212.5) == "3:32.5")
        #expect(Clock.text(59.9999) == "1:00")
        #expect(Clock.text(1.25) == "0:01.25")
        #expect(Clock.text(.nan) == "0:00")
        for seconds in [0, 45, 212.5, 3599.125] { #expect(Clock.seconds(from: Clock.text(seconds)) == seconds) }
    }
}
