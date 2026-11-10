import Foundation
import Testing

@testable import CueCore

let designMovieJSON = """
    { "format": 1, "title": "The Greatest Showman", "colour": "#7a4aff",
      "items": [
        { "type": "clip", "number": 0, "file": "clips/00_title.mp4", "title": "Title",
          "planned_end_s": 45, "tail_s": 0, "colour": "#444", "brief": "Pause on title, wait for conductor" },
        { "type": "clip", "number": 1, "file": "clips/01_the_greatest_show.mp4", "title": "The Greatest Show",
          "planned_end_s": 212.5, "tail_s": 60 },
        { "type": "black" } ] }
    """

let designConcertJSON = """
    { "format": 1, "title": "Spring Gala 2026", "logos": ["logos/orchestra.png", "logos/event.png"],
      "items": [
        { "type": "black" },
        { "type": "movie", "file": "showman.movie.json" },
        { "type": "break", "minutes": 20, "countdown": true, "text": "Szünet" },
        { "type": "logo", "logo": 1 } ] }
    """

let designMovie = Movie(
    title: "The Greatest Showman",
    colour: "#7a4aff",
    items: [
        .clip(
            Clip(
                file: "clips/00_title.mp4", number: 0, title: "Title", plannedEndS: 45, tailS: 0, colour: "#444",
                brief: "Pause on title, wait for conductor")),
        .clip(
            Clip(
                file: "clips/01_the_greatest_show.mp4", number: 1, title: "The Greatest Show", plannedEndS: 212.5,
                tailS: 60)),
        .black,
    ])

let designConcert = Concert(
    title: "Spring Gala 2026",
    logos: [.image("logos/orchestra.png"), .image("logos/event.png")],
    items: [
        .black,
        .movie(MovieRef(file: "showman.movie.json")),
        .breakScreen(BreakItem(minutes: 20, countdown: true, text: "Szünet")),
        .logo(LogoItem(logo: 1)),
    ])

func withTempDir(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cue-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}

func write(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

func jsonObject(_ data: Data) throws -> NSDictionary {
    try #require(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

@Suite struct ContentModelTests {
    @Test func designMovieParses() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("showman.movie.json")
            try write(designMovieJSON, to: url)
            #expect(try ShowLoader.loadMovie(at: url) == designMovie)
        }
    }

    @Test func designConcertParses() throws {
        try withTempDir { dir in
            try write(designMovieJSON, to: dir.appendingPathComponent("showman.movie.json"))
            let url = dir.appendingPathComponent("gala-2026.concert.json")
            try write(designConcertJSON, to: url)
            let loaded = try ShowLoader.loadConcert(at: url)
            #expect(loaded.concert == designConcert)
            #expect(Array(loaded.movies.values) == [designMovie])
        }
    }

    @Test func designFilesRoundTripToTheSameJSON() throws {
        try withTempDir { dir in
            let movieURL = dir.appendingPathComponent("a.movie.json")
            let concertURL = dir.appendingPathComponent("a.concert.json")
            try ShowLoader.save(designMovie, to: movieURL)
            try ShowLoader.save(designConcert, to: concertURL)

            let movieData = try Data(contentsOf: movieURL)
            let concertData = try Data(contentsOf: concertURL)
            #expect(try jsonObject(movieData) == jsonObject(Data(designMovieJSON.utf8)))
            #expect(try jsonObject(concertData) == jsonObject(Data(designConcertJSON.utf8)))
            #expect(try ShowLoader.loadMovie(at: movieURL) == designMovie)

            let text = String(decoding: movieData, as: UTF8.self)
            #expect(!text.contains("\\/"))
            #expect(text.contains("\n"))
            #expect(text.hasSuffix("}\n"))
            #expect(String(decoding: concertData, as: UTF8.self).contains("Szünet"))
        }
    }

    // As the app saved it before logos had names; a loop keeps its form, whatever the file's extension.
    @Test func oldLogoFormsLoadUnnamedAndSaveBackByteForByte() throws {
        let old = """
            {
              "format" : 1,
              "items" : [
                {
                  "type" : "black"
                }
              ],
              "logos" : [
                null,
                "",
                "logos/a.png",
                {
                  "loop" : "logos/b.gif"
                }
              ],
              "title" : "Gala"
            }
            """ + "\n"
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.concert.json")
            try write(old, to: url)
            let concert = try ShowLoader.loadConcert(at: url).concert
            #expect(concert.logos == [nil, .image(""), .image("logos/a.png"), .loop("logos/b.gif")])
            try ShowLoader.save(concert, to: url)
            #expect(try String(contentsOf: url, encoding: .utf8) == old)
        }
    }

    @Test func aNamedLogoIsASlotEntryLoopingByItsExtension() throws {
        let json = #"""
            { "format": 1, "title": "T", "items": [],
              "logos": [{ "name": "Blades of Chaos", "file": "logos/b.MP4" },
                        { "name": "Marika néni kávézója", "file": "logos/m.png" }] }
            """#
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(
            concert.logos == [
                .loop("logos/b.MP4", name: "Blades of Chaos"), .image("logos/m.png", name: "Marika néni kávézója"),
            ])
        #expect(try jsonObject(JSONEncoder().encode(concert)) == jsonObject(Data(json.utf8)))
    }

    @Test func anOldConcertFileSavesBackWithoutASlotsKey() throws {
        let json = #"{ "format": 1, "title": "T", "logos": ["a.png", ""], "items": [{ "type": "logo", "logo": 2 }] }"#
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        #expect(concert.logos == [.image("a.png"), .image("")])
        #expect(concert.slots.isEmpty)
        #expect(try jsonObject(JSONEncoder().encode(concert)) == jsonObject(Data(json.utf8)))
    }

    @Test func overridesSaveAsNullEmptyOrObjectWithTrailingDefaultsDropped() throws {
        let sponsor = SlotEntry(name: "Sponsor 2026", file: "slots/sponsor.png")
        let concert = Concert(
            title: "T", logos: [nil, .image(""), nil], slots: [.useDefault, .own(sponsor), .empty, .useDefault])
        let json = #"""
            { "format": 1, "title": "T", "logos": [null, ""],
              "slots": [null, { "name": "Sponsor 2026", "file": "slots/sponsor.png" }, ""], "items": [] }
            """#
        let encoded = try JSONEncoder().encode(concert)
        #expect(try jsonObject(encoded) == jsonObject(Data(json.utf8)))
        #expect(try JSONDecoder().decode(Concert.self, from: encoded) == concert.trimmed)

        let defaults = Concert(title: "T", logos: [nil, nil], slots: [.useDefault, .useDefault])
        let plain = try jsonObject(JSONEncoder().encode(defaults))
        #expect(plain["slots"] == nil)
        #expect((plain["logos"] as? [Any])?.isEmpty == true)
    }

    @Test func aSlotIsNullEmptyOrAnObjectButNeverABarePath() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("a.concert.json")
            try write(#"{ "format": 1, "title": "T", "slots": [null, "x.png"] }"#, to: url)
            #expect {
                try ShowLoader.loadConcert(at: url)
            } throws: { error in
                guard case ShowError.invalidJSON(_, let message) = error else { return false }
                return message.contains(".slots[1]")
            }
        }
    }

    @Test func absentListsDecodeAsEmpty() throws {
        let concert = try JSONDecoder().decode(Concert.self, from: Data(#"{ "format": 1, "title": "T" }"#.utf8))
        #expect(concert.logos.isEmpty)
        #expect(concert.slots.isEmpty)
        #expect(concert.items.isEmpty)
        let movie = try JSONDecoder().decode(Movie.self, from: Data(#"{ "format": 1, "title": "T" }"#.utf8))
        #expect(movie.items.isEmpty)
    }

    @Test func breakCountdownDefaultsToOff() throws {
        let json = #"{ "type": "break", "minutes": 5 }"#
        let item = try JSONDecoder().decode(Item.self, from: Data(json.utf8))
        #expect(item == .breakScreen(BreakItem(minutes: 5, countdown: false, text: nil)))
    }

    @Test(arguments: [
        ("01_the_greatest_show.mp4", 1, "The Greatest Show"),
        ("clips/00_title.mp4", 0, "Title"),
        ("12_x.mov", 12, "X"),
    ])
    func filenameSuppliesNumberAndTitle(file: String, number: Int, title: String) {
        let clip = Clip(file: file)
        #expect(clip.resolvedNumber == number)
        #expect(clip.resolvedTitle == title)
    }

    @Test func explicitNumberAndTitleBeatTheFilename() {
        let clip = Clip(file: "01_the_greatest_show.mp4", number: 7, title: "Overture")
        #expect(clip.resolvedNumber == 7)
        #expect(clip.resolvedTitle == "Overture")
    }

    @Test(arguments: [
        ("intro_music.mp4", "Intro Music"),
        ("clips/intro_music.mp4", "Intro Music"),
        ("x1_intro.mp4", "X1 Intro"),
    ])
    func filenameWithoutNumberPrefixHasNoNumber(file: String, title: String) {
        let clip = Clip(file: file)
        #expect(clip.resolvedNumber == nil)
        #expect(clip.resolvedTitle == title)
    }
}
