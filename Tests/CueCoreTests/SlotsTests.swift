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
