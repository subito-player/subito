import Foundation
import Testing

@testable import CueCore

private let concertURL = URL(fileURLWithPath: "/show/gala.concert.json")

private let defaults = SlotSet(
    logos: [.image("/set/orchestra.png"), .loop("/set/event.mp4")],
    slots: [
        SlotEntry(name: "Sponsor", file: "/set/sponsor.png"), SlotEntry(name: "Thanks", file: "/set/thanks.MOV"), nil,
        SlotEntry(name: "Interval", file: "/set/interval.m4v"), SlotEntry(name: "Gone", file: ""),
    ])

private func image(_ path: String) -> LogoFile {
    .image(URL(fileURLWithPath: path))
}

private func loop(_ path: String) -> LogoFile {
    .loop(URL(fileURLWithPath: path))
}

private func merge(_ concert: Concert?) -> [Picture?] {
    Pictures.merge(defaults: defaults, concert: concert, concertURL: concertURL)
}

@Suite struct PictureMergeTests {
    private let defaultLogo1 = Picture(name: "Logo 1", file: image("/set/orchestra.png"), source: .defaultSet)
    private let defaultLogo2 = Picture(name: "Logo 2", file: loop("/set/event.mp4"), source: .defaultSet)
    private let defaultSlot1 = Picture(name: "Sponsor", file: image("/set/sponsor.png"), source: .defaultSet)
    private let defaultSlot2 = Picture(name: "Thanks", file: loop("/set/thanks.MOV"), source: .defaultSet)
    private let defaultSlot4 = Picture(name: "Interval", file: loop("/set/interval.m4v"), source: .defaultSet)

    // A single movie open: the default set alone, videos looping by their extension.
    @Test func withoutAConcertTheDefaultSetShows() {
        #expect(merge(nil) == [defaultLogo1, defaultLogo2, defaultSlot1, defaultSlot2, nil, defaultSlot4, nil, nil])
    }

    @Test func alwaysEightPicturesAndAThirdLogoNeverBecomesASlot() {
        #expect(Pictures.merge(defaults: SlotSet(), concert: nil, concertURL: nil) == Array(repeating: nil, count: 8))
        let pictures = merge(Concert(title: "T", logos: [.image("a.png"), .image("b.png"), .image("c.png")]))
        #expect(pictures.count == 8)
        #expect(pictures[2] == defaultSlot1)
    }

    @Test func aConcertsOwnPictureReplacesTheDefaultResolvedAgainstTheConcert() {
        let concert = Concert(
            title: "T", logos: [.image("logos/own.png")],
            slots: [
                .own(SlotEntry(name: "Sponsor 2026", file: "slots/sponsor.mp4")), .useDefault,
                .own(SlotEntry(name: "Encore", file: "/Volumes/Stage/encore.png")),
            ])
        let pictures = merge(concert)
        #expect(pictures[0] == Picture(name: "Logo 1", file: image("/show/logos/own.png"), source: .concert))
        #expect(pictures[2] == Picture(name: "Sponsor 2026", file: loop("/show/slots/sponsor.mp4"), source: .concert))
        #expect(pictures[4] == Picture(name: "Encore", file: image("/Volumes/Stage/encore.png"), source: .concert))
        #expect(pictures[1] == defaultLogo2)
        #expect(pictures[3] == defaultSlot2)
    }

    @Test func emptyInThisConcertHidesTheDefault() {
        let pictures = merge(Concert(title: "T", logos: [.image(""), .loop("")], slots: [.empty, .empty]))
        #expect(pictures.prefix(4) == [nil, nil, nil, nil])
        #expect(pictures[5] == defaultSlot4)
    }

    @Test func nullOrMissingKeepsTheDefault() {
        let pictures = merge(Concert(title: "T", logos: [nil], slots: [.useDefault]))
        #expect(pictures == merge(nil))
        #expect(merge(Concert(title: "T")) == merge(nil))
    }

    // "" is empty in this concert, so an old file's gap hides the default logo.
    @Test func anOldConcertFileKeepsItsLogosAndGetsTheDefaultSlots() throws {
        let json = #"{ "format": 1, "title": "Gala", "logos": ["logos/a.png", ""], "items": [] }"#
        let concert = try JSONDecoder().decode(Concert.self, from: Data(json.utf8))
        let pictures = merge(concert)
        #expect(pictures[0] == Picture(name: "Logo 1", file: image("/show/logos/a.png"), source: .concert))
        #expect(pictures[1] == nil)
        #expect(Array(pictures[2...]) == Array(merge(nil)[2...]))
    }
}

@Suite struct SlotSetTests {
    @Test func theDefaultSetFileHoldsLogosAndSlotsWithGaps() throws {
        let json = #"""
            { "format": 1, "logos": [null, { "loop": "/set/event.mp4" }],
              "slots": [null, { "name": "Thanks", "file": "/set/thanks.mov" }] }
            """#
        let set = try JSONDecoder().decode(SlotSet.self, from: Data(json.utf8))
        #expect(
            set
                == SlotSet(
                    logos: [nil, .loop("/set/event.mp4")],
                    slots: [nil, SlotEntry(name: "Thanks", file: "/set/thanks.mov")]))
        #expect(try JSONDecoder().decode(SlotSet.self, from: JSONEncoder().encode(set)) == set)
        #expect(try JSONDecoder().decode(SlotSet.self, from: Data(#"{ "format": 1 }"#.utf8)) == SlotSet())
    }
}

@Suite struct DefaultSetFileTests {
    @Test func aMissingFileIsTheEmptySet() throws {
        try withTempDir { dir in
            let (set, error) = SlotSet.load(from: dir.appendingPathComponent(SlotSet.fileName))
            #expect(set == SlotSet())
            #expect(error == nil)
        }
    }

    // The owner's hand edit with a typo is reported, loads as empty, and survives the first save from the app.
    @Test func aBrokenFileIsKeptAsideNeverSavedOver() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent(SlotSet.fileName)
            let broken = #"{ "format": 1, "slots": [{ "name": "Thanks" }] }"#
            try write(broken, to: url)
            let (set, error) = SlotSet.load(from: url)
            #expect(set == SlotSet())
            guard case .invalidJSON? = error else {
                Issue.record("expected invalidJSON, got \(String(describing: error))")
                return
            }
            #expect(try String(contentsOf: url, encoding: .utf8) == broken)

            var changed = SlotSet()
            changed.setPicture(3, .own(SlotEntry(name: "Sponsor", file: "/set/sponsor.png")))
            let aside = try changed.save(to: url, overBroken: true)
            #expect(try aside.map { try String(contentsOf: $0, encoding: .utf8) } == broken)
            #expect(aside?.lastPathComponent.wholeMatch(of: /slots\.broken-\d{8}-\d{6}\.json/) != nil)
            let (reloaded, reloadError) = SlotSet.load(from: url)
            #expect(reloaded == changed)
            #expect(reloadError == nil)
        }
    }

    // A second broken file is set aside next to the first, never over it.
    @Test func everyBrokenFileIsKept() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent(SlotSet.fileName)
            let first = Date(timeIntervalSince1970: 1_700_000_000)
            try write("first", to: url)
            #expect(try SlotSet().save(to: url, overBroken: true, now: first) == SlotSet.brokenURL(for: url, at: first))
            try write("second", to: url)
            let second = first.addingTimeInterval(60)
            #expect(
                try SlotSet().save(to: url, overBroken: true, now: second) == SlotSet.brokenURL(for: url, at: second))
            #expect(try String(contentsOf: SlotSet.brokenURL(for: url, at: first), encoding: .utf8) == "first")
            #expect(try String(contentsOf: SlotSet.brokenURL(for: url, at: second), encoding: .utf8) == "second")
            #expect(try SlotSet().save(to: url, overBroken: false) == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 3)
        }
    }

    @Test func aNewerFormatIsReportedNotRead() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent(SlotSet.fileName)
            try write(#"{ "format": 2, "logos": ["/set/a.png"] }"#, to: url)
            let (set, error) = SlotSet.load(from: url)
            #expect(set == SlotSet())
            #expect(error == .unsupportedFormat(file: url, format: 2))
        }
    }

    // Clearing a picture leaves no null tail, so an emptied set saves as a bare format.
    @Test func settingADefaultPictureStoresItAndClearingRemovesIt() {
        var set = SlotSet()
        set.setPicture(2, .own(SlotEntry(name: "", file: "/set/event.mov")))
        set.setPicture(4, .own(SlotEntry(name: "Thanks", file: "/set/thanks.png")))
        #expect(
            set
                == SlotSet(
                    logos: [nil, .loop("/set/event.mov")],
                    slots: [nil, SlotEntry(name: "Thanks", file: "/set/thanks.png")]))
        set.setPicture(4, .empty)
        set.setPicture(2, .useDefault)
        #expect(set == SlotSet())
    }
}

@Suite struct CoverRefusalTests {
    private func refuses(_ command: Command, cover: Cover?, showable: Set<Int>) -> Bool {
        ShowState.refusesCover(command, cover: cover, showable: showable)
    }

    @Test func anEmptyOrUnloadedPictureNeverComesOn() {
        #expect(refuses(.toggleCover(.logo(5)), cover: nil, showable: [1, 2, 3]))
        // Logo 1 stays up: a stray slot press does not swap it for black.
        #expect(refuses(.toggleCover(.logo(5)), cover: .logo(1), showable: [1, 2, 3]))
        #expect(refuses(.toggleCover(.logo(1)), cover: .black, showable: []))
    }

    @Test func theShownPictureAlwaysGoesOffEvenIfItsFileVanished() {
        #expect(!refuses(.toggleCover(.logo(5)), cover: .logo(5), showable: []))
    }

    @Test func aLoadedPictureComesOnOrSwaps() {
        #expect(!refuses(.toggleCover(.logo(5)), cover: nil, showable: [5]))
        #expect(!refuses(.toggleCover(.logo(2)), cover: .logo(5), showable: [2]))
    }

    @Test func blackAndOtherCommandsAreNeverRefused() {
        #expect(!refuses(.toggleCover(.black), cover: nil, showable: []))
        #expect(!refuses(.toggleCover(.black), cover: .logo(3), showable: []))
        #expect(!refuses(.go, cover: nil, showable: []))
    }
}

@Suite struct PictureWriteTests {
    private let sponsor = Picture(name: "Sponsor", file: image("/set/sponsor.png"), source: .defaultSet)

    private func write(_ change: PictureChange, _ number: Int, _ shown: Picture?, _ scope: PictureScope)
        -> PictureWrite?
    {
        Pictures.write(change, to: number, shown: shown, scope: scope)
    }

    // A concert's own copy of a default slot with only the file changed keeps the default's name.
    @Test func aNewFileKeepsTheNameShown() {
        let entry = SlotOverride.own(SlotEntry(name: "Sponsor", file: "/show/slots/sponsor.mp4"))
        #expect(write(.file("/show/slots/sponsor.mp4"), 3, sponsor, .thisConcert) == .concert(entry))
        #expect(write(.file("/show/slots/sponsor.mp4"), 3, sponsor, .everyConcert) == .defaultSet(entry))
        #expect(
            write(.file("/set/new.png"), 4, nil, .thisConcert)
                == .concert(.own(SlotEntry(name: "", file: "/set/new.png"))))
    }

    // The shown file is the resolved absolute path; the concert edit stores it relative again.
    @Test func aNewNameKeepsTheFileShown() {
        let own = Picture(name: "Sponsor", file: loop("/show/slots/sponsor.mp4"), source: .concert)
        #expect(
            write(.name("Sponsor 2026"), 3, own, .thisConcert)
                == .concert(.own(SlotEntry(name: "Sponsor 2026", file: "/show/slots/sponsor.mp4"))))
        #expect(
            write(.name("Thanks"), 3, sponsor, .everyConcert)
                == .defaultSet(.own(SlotEntry(name: "Thanks", file: "/set/sponsor.png"))))
        #expect(write(.name("Encore"), 5, nil, .thisConcert) == nil)
    }

    // Logos have no name: "Logo 1" on the button comes from the merge, never from the file.
    @Test func aLogoIsWrittenWithoutAName() {
        let logo = Picture(name: "Logo 1", file: image("/set/orchestra.png"), source: .defaultSet)
        #expect(
            write(.file("/set/event.mov"), 1, logo, .everyConcert)
                == .defaultSet(.own(SlotEntry(name: "", file: "/set/event.mov"))))
        #expect(write(.name("Orchestra"), 1, logo, .thisConcert) == nil)
    }

    @Test func emptyGoesWhereTheScopeSays() {
        #expect(write(.empty, 3, sponsor, .thisConcert) == .concert(.empty))
        #expect(write(.empty, 3, sponsor, .everyConcert) == .defaultSet(.empty))
    }
}
