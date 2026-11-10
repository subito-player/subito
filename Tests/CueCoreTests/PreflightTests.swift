import Foundation
import Testing

@testable import CueCore

private let ownExport = ClipProbe(
    exists: true, playable: true, width: 1920, height: 1080, fps: 24000.0 / 1001, codec: "avc1", duration: 272.5,
    hasVideo: true, hasAudio: true)
private let planned = Clip(file: "clips/01_x.mp4", plannedEndS: 212.5, tailS: 60)

private func kinds(_ findings: [Finding]) -> [Finding.Kind] {
    findings.map(\.kind)
}

private func probe(_ change: (inout ClipProbe) -> Void) -> ClipProbe {
    var probe = ownExport
    change(&probe)
    return probe
}

@Suite struct ClipPreflightTests {
    @Test func ownExportPassesClean() {
        #expect(Preflight.evaluate(clip: planned, probe: ownExport) == [])
    }

    @Test func missingUnplayableOrPictureless() {
        #expect(
            Preflight.evaluate(clip: planned, probe: ClipProbe())
                == [Finding(severity: .block, kind: .fileMissing, detail: "clips/01_x.mp4")])
        #expect(
            Preflight.evaluate(clip: planned, probe: ClipProbe(exists: true))
                == [Finding(severity: .block, kind: .notPlayable, detail: "clips/01_x.mp4")])
        let audioOnly = ClipProbe(exists: true, playable: true, duration: 272.5, hasAudio: true)
        #expect(
            Preflight.evaluate(clip: planned, probe: audioOnly)
                == [Finding(severity: .block, kind: .noVideo, detail: "clips/01_x.mp4")])
    }

    @Test func otherSizeAndRateStillPlayWithAWarning() {
        let other = probe {
            $0.width = 1280
            $0.height = 720
            $0.fps = 25
        }
        #expect(
            Preflight.evaluate(clip: planned, probe: other) == [
                Finding(severity: .warn, kind: .size, detail: "1280x720"),
                Finding(severity: .warn, kind: .frameRate, detail: "25 fps"),
            ])
        #expect(kinds(Preflight.evaluate(clip: planned, probe: probe { $0.height = 1088 })) == [.size])
    }

    @Test(arguments: [
        (23.976, true), (23.9859, true), (23.9661, true), (23.9861, false), (23.9659, false), (24, false),
        (29.97, false),
    ])
    func frameRateWithinAHundredthOfFilmRate(fps: Double, fine: Bool) {
        let findings = Preflight.evaluate(clip: planned, probe: probe { $0.fps = fps })
        #expect(kinds(findings) == (fine ? [] : [.frameRate]))
    }

    // Own exports end 1 s (the fade) after planned + tail, give or take a frame.
    @Test(arguments: [
        (272.5, true), (273.5, true), (273.5 + 1001.0 / 24000, true), (273.54, true), (271.46, true), (273.56, false),
        (271.44, false),
    ])
    func lengthWithinOneSecondAndAFrameOfPlannedEndPlusTail(duration: Double, fine: Bool) {
        let findings = Preflight.evaluate(clip: planned, probe: probe { $0.duration = duration })
        #expect(kinds(findings) == (fine ? [] : [.length]))
    }

    @Test func lengthDetailShowsClipThenPlannedPlusTail() {
        let findings = Preflight.evaluate(clip: planned, probe: probe { $0.duration = 280 })
        #expect(findings == [Finding(severity: .warn, kind: .length, detail: "4:40.0 / 4:32.5")])
    }

    @Test func lengthNeedsBothPlannedEndAndTail() {
        let short = probe { $0.duration = 230 }
        #expect(Preflight.evaluate(clip: Clip(file: "x.mp4", plannedEndS: 212.5), probe: short) == [])
        #expect(Preflight.evaluate(clip: Clip(file: "x.mp4", tailS: 60), probe: short) == [])
        #expect(Preflight.evaluate(clip: Clip(file: "x.mp4"), probe: short) == [])
    }

    @Test func plannedEndPastTheClipEnd() {
        let clip = Clip(file: "x.mp4", plannedEndS: 100)
        #expect(Preflight.evaluate(clip: clip, probe: probe { $0.duration = 100 }) == [])
        #expect(
            Preflight.evaluate(clip: clip, probe: probe { $0.duration = 99.9 })
                == [Finding(severity: .warn, kind: .plannedEnd, detail: "1:40.0 / 1:39.9")])
        let withTail = Clip(file: "x.mp4", plannedEndS: 100, tailS: 0)
        #expect(kinds(Preflight.evaluate(clip: withTail, probe: probe { $0.duration = 90 })) == [.length, .plannedEnd])
    }

    @Test func cueFindingsCarryTheirIndexAndUnprobedFilesCountAsMissing() {
        let good = URL(fileURLWithPath: "/show/01_x.mp4")
        let other = URL(fileURLWithPath: "/show/02_y.mp4")
        let cues = [
            Cue(kind: .black, movieIndex: nil),
            Cue(kind: .clip(planned, good), movieIndex: 0),
            Cue(kind: .clip(Clip(file: "02_y.mp4"), other), movieIndex: 0),
            Cue(kind: .clip(Clip(file: "03_z.mp4"), URL(fileURLWithPath: "/show/03_z.mp4")), movieIndex: 0),
        ]
        let findings = Preflight.evaluate(
            cues: cues, probes: [good: ownExport, other: probe { $0.fps = 25 }], logos: [])
        #expect(
            findings == [
                Finding(severity: .warn, cueIndex: 2, kind: .frameRate, detail: "25 fps"),
                Finding(severity: .block, cueIndex: 3, kind: .fileMissing, detail: "03_z.mp4"),
            ])
    }

    @Test func logoCueAboveTheLogoCountWarns() {
        let cues = [1, 2, 3].map { Cue(kind: .logo($0), movieIndex: nil) }
        let two = [image("a.png"), image("b.png")]
        #expect(
            Preflight.evaluate(cues: cues, probes: [:], logos: two) == [
                Finding(severity: .warn, cueIndex: 2, kind: .logoNumber, detail: "3")
            ])
        #expect(Preflight.evaluate(cues: cues, probes: [:], logos: []).map(\.cueIndex) == [0, 1, 2])
        #expect(Preflight.evaluate(cues: cues, probes: [:], logos: two + [loop("c.mp4")]) == [])
    }

    @Test func logoCueOnANumberWithNoFileWarns() {
        let cues = [1, 2].map { Cue(kind: .logo($0), movieIndex: nil) }
        #expect(
            Preflight.evaluate(cues: cues, probes: [:], logos: [nil, loop("b.mp4")]) == [
                Finding(severity: .warn, cueIndex: 0, kind: .logoNumber, detail: "1")
            ])
    }
}

private func image(_ name: String) -> LogoFile {
    .image(URL(fileURLWithPath: "/show/logos/\(name)"))
}

private func loop(_ name: String) -> LogoFile {
    .loop(URL(fileURLWithPath: "/show/logos/\(name)"))
}

@Suite struct LogoPreflightTests {
    @Test func aLogoThatDidNotLoadWarnsWithItsNumberAndFileName() {
        let logos = ["a.png", "b.png", "c.png"].map(image)
        let urls = logos.map(\.url)
        #expect(Preflight.evaluate(logos: logos, images: Set(urls), probes: [:]) == [])
        #expect(
            Preflight.evaluate(logos: logos, images: [urls[0]], probes: [:]) == [
                Finding(severity: .warn, kind: .logo, detail: "2 · b.png"),
                Finding(severity: .warn, kind: .logo, detail: "3 · c.png"),
            ])
    }

    @Test func aBrokenLoopWarnsLikeAMissingImageButNeverBlocks() {
        let logos = [loop("a.mp4"), loop("b.mp4"), loop("c.mp4"), loop("d.mp4")]
        let probes = [
            logos[0].url: ownExport,
            logos[1].url: ClipProbe(),
            logos[2].url: probe { $0.playable = false },
            logos[3].url: probe { $0.hasVideo = false },
        ]
        #expect(
            Preflight.evaluate(logos: logos, images: [], probes: probes) == [
                Finding(severity: .warn, kind: .logo, detail: "2 · b.mp4"),
                Finding(severity: .warn, kind: .logo, detail: "3 · c.mp4"),
                Finding(severity: .warn, kind: .logo, detail: "4 · d.mp4"),
            ])
    }

    @Test func aLoopIsNotJudgedOnClipWarningsOrBeforeItsProbe() {
        let odd = probe {
            $0.width = 1280
            $0.fps = 30
            $0.hasAudio = false
        }
        let logos = [loop("a.mp4"), loop("b.mp4")]
        #expect(Preflight.evaluate(logos: logos, images: [], probes: [logos[0].url: odd]) == [])
    }

    @Test func aNumberWithNoFileIsLeftToTheLogoCues() {
        #expect(Preflight.evaluate(logos: [nil, image("b.png")], images: [image("b.png").url], probes: [:]) == [])
    }
}

@Suite struct SystemPreflightTests {
    private func system(_ change: (inout SystemProbe) -> Void = { _ in }) -> [Finding] {
        var probe = SystemProbe(
            projectorName: "Epson", refreshHz: 24, availableHz: [24, 60], soundDevice: "MacBook Pro Speakers")
        change(&probe)
        return Preflight.evaluate(system: probe)
    }

    @Test func goodRigIsAllOk() {
        #expect(
            system() == [
                Finding(severity: .ok, kind: .projector, detail: "Epson"),
                Finding(severity: .ok, kind: .refreshRate, detail: "24 Hz (24, 60)"),
                Finding(severity: .ok, kind: .power),
                Finding(severity: .ok, kind: .spaces),
                Finding(severity: .ok, kind: .sound, detail: "MacBook Pro Speakers"),
            ])
    }

    @Test func missingOrMirroredProjectorBlocks() {
        let missing = system { $0.projector = false }
        #expect(missing.first == Finding(severity: .block, kind: .projector))
        #expect(!kinds(missing).contains(.refreshRate))
        #expect(system { $0.mirrored = true }.first == Finding(severity: .block, kind: .mirrored, detail: "Epson"))
    }

    @Test func batterySpanningSpacesAndSoundToTheDisplayWarn() {
        let findings = system {
            $0.onBattery = true
            $0.spansDisplays = true
            $0.soundDevice = "EPSON PJ"
            $0.soundToDisplay = true
        }
        #expect(
            Array(findings.suffix(3)) == [
                Finding(severity: .warn, kind: .power),
                Finding(severity: .warn, kind: .spaces),
                Finding(severity: .warn, kind: .sound, detail: "EPSON PJ"),
            ])
    }

    @Test func betterRateIsInformationOnly() {
        let findings = system {
            $0.refreshHz = 60
            $0.availableHz = [60, 50, 23.976023, 24, 60.000_4]
        }
        #expect(
            findings[1]
                == Finding(severity: .ok, kind: .betterRefreshRate, detail: "60 Hz → 23.976 Hz (23.976, 24, 50, 60)"))
        #expect(system { $0.refreshHz = 0 }[1] == Finding(severity: .ok, kind: .refreshRate, detail: "? Hz (24, 60)"))
    }

    @Test(
        arguments: [
            ([60, 24, 72, 47.952048, 71.928072, 23.976023], 23.976023),
            ([60, 24, 48, 72, 71.928072, 47.952048], 47.952048),
            ([60, 24, 48, 72, 71.928072], 71.928072), ([60, 72, 48, 24], 24), ([60, 72, 48], 48), ([60, 72], 72),
            ([50, 60, 75], 60), ([120, 165, 60], 60), ([59.94, 60.004], 60.004),
        ] as [([Double], Double)])
    func recommendationOrder(available: [Double], best: Double) {
        #expect(Preflight.recommendedRate(among: available) == best)
    }

    @Test func noPreferredRateMeansNoRecommendation() {
        #expect(Preflight.recommendedRate(among: [50, 75]) == nil)
        let findings = system {
            $0.refreshHz = 50
            $0.availableHz = [50, 75]
        }
        #expect(findings[1] == Finding(severity: .ok, kind: .refreshRate, detail: "50 Hz (50, 75)"))
    }
}
