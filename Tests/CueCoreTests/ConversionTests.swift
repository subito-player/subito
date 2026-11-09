import Foundation
import Testing

@testable import CueCore

private let home = "/Users/op"
private let ffmpegPaths = Conversion.ffmpegPaths(home: home, user: "op")
private let nixPaths = Conversion.nixPaths(home: home, user: "op")

private func locate(_ present: Set<String>) -> Conversion.Tool? {
    Conversion.locate(ffmpeg: ffmpegPaths, nix: nixPaths, exists: present.contains)
}

private let playsWithSound = ClipProbe(exists: true, playable: true, codec: "avc1", hasVideo: true, hasAudio: true)
private let playsSilent = ClipProbe(exists: true, playable: true, codec: "hvc1", hasVideo: true)
private let doesNotPlay = ClipProbe(exists: true, codec: "vp09", hasVideo: true)

@Suite struct ConversionToolTests {
    @Test func homebrewThenUsrLocalThenNixProfilesForAnInstalledFfmpeg() {
        #expect(
            ffmpegPaths == [
                "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/Users/op/.nix-profile/bin/ffmpeg",
                "/etc/profiles/per-user/op/bin/ffmpeg", "/run/current-system/sw/bin/ffmpeg",
            ])
        let both: Set = ["/opt/homebrew/bin/ffmpeg", "/opt/homebrew/bin/ffprobe", "/Users/op/.nix-profile/bin/ffmpeg"]
        #expect(
            locate(both)
                == .installed(
                    Conversion.Binaries(ffmpeg: "/opt/homebrew/bin/ffmpeg", ffprobe: "/opt/homebrew/bin/ffprobe")))
        #expect(
            locate(["/etc/profiles/per-user/op/bin/ffmpeg", "/nix/var/nix/profiles/default/bin/nix"])
                == .installed(Conversion.Binaries(ffmpeg: "/etc/profiles/per-user/op/bin/ffmpeg")))
    }

    @Test func aNixBinaryRunsFfmpegThroughNixShellWhenNoneIsInstalled() {
        #expect(locate(["/Users/op/.nix-profile/bin/nix"]) == .nix("/Users/op/.nix-profile/bin/nix"))
        #expect(
            locate(["/nix/var/nix/profiles/default/bin/nix", "/run/current-system/sw/bin/nix"]) == .nix(nixPaths[0]))
        #expect(locate(["/opt/homebrew/bin/ffprobe", "/usr/bin/nix"]) == nil)
    }

    @Test func nixResolvesStorePathsOfflineFirstThenOnline() {
        let tail = ["nixpkgs#ffmpeg", "--command", "/bin/sh", "-c", "command -v ffmpeg; command -v ffprobe"]
        let head = ["--extra-experimental-features", "nix-command flakes", "shell"]
        #expect(
            Conversion.resolveInvocation(nix: "/n/nix", offline: true)
                == Conversion.Invocation(executable: "/n/nix", arguments: head + ["--offline"] + tail))
        #expect(
            Conversion.resolveInvocation(nix: "/n/nix", offline: false)
                == Conversion.Invocation(executable: "/n/nix", arguments: head + tail))
    }

    @Test func resolvedPathsComeFromTheShellOutput() {
        let store = "/nix/store/a5ps-ffmpeg-9.0.2-bin/bin"
        #expect(
            Conversion.binaries(fromResolveOutput: "\(store)/ffmpeg\n\(store)/ffprobe\n")
                == Conversion.Binaries(ffmpeg: "\(store)/ffmpeg", ffprobe: "\(store)/ffprobe"))
        #expect(
            Conversion.binaries(fromResolveOutput: "\(store)/ffmpeg\n")
                == Conversion.Binaries(ffmpeg: "\(store)/ffmpeg"))
        #expect(Conversion.binaries(fromResolveOutput: "") == nil)
        #expect(Conversion.binaries(fromResolveOutput: "ffmpeg\nerror: cannot download") == nil)
    }

    @Test func onlyOurOwnToolIsAnOrphanAfterACrash() {
        let written = Date(timeIntervalSinceReferenceDate: 1000)
        #expect(Conversion.isOrphan(name: "ffmpeg", startedAt: written - 0.2, pidWrittenAt: written))
        #expect(Conversion.isOrphan(name: "nix", startedAt: nil, pidWrittenAt: nil))
        #expect(Conversion.isOrphan(name: "ffprobe", startedAt: written, pidWrittenAt: nil))
        // The pid went to a later process, such as an ffmpeg started by hand.
        #expect(!Conversion.isOrphan(name: "ffmpeg", startedAt: written + 3600, pidWrittenAt: written))
        #expect(!Conversion.isOrphan(name: "Safari", startedAt: written, pidWrittenAt: written))
        #expect(!Conversion.isOrphan(name: nil, startedAt: nil, pidWrittenAt: written))
    }
}

@Suite struct ConversionPlanTests {
    private let source = URL(fileURLWithPath: "/show/clips/03_dance.mkv")

    @Test func outputSitsNextToTheOriginalAndNeverTakesAnExistingName() {
        #expect(Conversion.outputURL(for: source) { _ in false }.path == "/show/clips/03_dance.mp4")
        var taken: Set = ["/show/clips/03_dance.mp4"]
        #expect(
            Conversion.outputURL(for: source) { taken.contains($0.path) }.path == "/show/clips/03_dance (converted).mp4"
        )
        taken.insert("/show/clips/03_dance (converted).mp4")
        taken.insert("/show/clips/03_dance (converted 2).mp4")
        #expect(
            Conversion.outputURL(for: source) { taken.contains($0.path) }.path
                == "/show/clips/03_dance (converted 3).mp4")
    }

    @Test func anUnplayableMp4IsNeverOverwrittenByItsOwnConversion() {
        let mp4 = URL(fileURLWithPath: "/show/clips/04_vp9.mp4")
        #expect(Conversion.outputURL(for: mp4) { $0 == mp4 }.path == "/show/clips/04_vp9 (converted).mp4")
    }

    @Test func theTempFileIsHiddenInTheSameFolderAndNeverAClipOfAnOpenedFolder() {
        let temp = Conversion.tempURL(for: source)
        #expect(temp.path == "/show/clips/.03_dance.converting.mp4")
        #expect(Clip(file: temp.lastPathComponent).resolvedNumber == nil)
    }

    @Test func remuxCopiesTheFirstPictureAndEveryAudioTrack() {
        let output = URL(fileURLWithPath: "/show/clips/.03_dance.converting.mp4")
        let head = [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-n", "-i",
            source.path, "-map", "0:v:0", "-map", "0:a?",
        ]
        let tail = ["-movflags", "+faststart", "-f", "mp4", output.path]
        #expect(
            Conversion.arguments(.remux, input: source, output: output, hevc: false) == head + ["-c", "copy"] + tail)
        #expect(
            Conversion.arguments(.remux, input: source, output: output, hevc: true)
                == head + ["-c", "copy", "-tag:v", "hvc1"] + tail)
        let transcode = [
            "-c:v", "h264_videotoolbox", "-b:v", "20M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k",
        ]
        #expect(Conversion.arguments(.transcode, input: source, output: output, hevc: true) == head + transcode + tail)
    }
}

@Suite struct ConversionProbeTests {
    @Test func ffprobeJSONGivesCodecAudioAndDuration() {
        let json = """
            { "programs": [], "stream_groups": [],
              "streams": [ { "codec_name": "hevc", "codec_type": "video" },
                           { "codec_name": "aac", "codec_type": "audio" } ],
              "format": { "duration": "10.023000" } }
            """
        #expect(
            Conversion.sourceInfo(json: Data(json.utf8))
                == Conversion.SourceInfo(videoCodec: "hevc", hasAudio: true, duration: 10.023))
    }

    @Test func missingPartsStayUnknown() {
        let silent =
            #"{ "streams": [ { "codec_name": "mpeg4", "codec_type": "video" } ], "format": { "duration": "N/A" } }"#
        #expect(Conversion.sourceInfo(json: Data(silent.utf8)) == Conversion.SourceInfo(videoCodec: "mpeg4"))
        #expect(Conversion.sourceInfo(json: Data("{\n\n}".utf8)) == Conversion.SourceInfo())
        #expect(Conversion.sourceInfo(json: Data("Invalid data found".utf8)) == nil)
    }

    @Test func progressReadsTheOutputTimeInMicroseconds() {
        #expect(Conversion.progressSeconds("out_time_us=5005000") == 5.005)
        #expect(Conversion.progressSeconds("out_time_us=N/A") == nil)
        #expect(Conversion.progressSeconds("out_time_us=-9223372036854775807") == nil)
        #expect(Conversion.progressSeconds("out_time_ms=5005000") == nil)
        #expect(Conversion.progressSeconds("progress=end") == nil)
    }

    @Test func aTranscodeNeedsRoomFor20MbitPerSecondPlusAFifth() {
        #expect(Conversion.transcodeBytes(duration: 100) == 300_000_000)
        #expect(Conversion.transcodeBytes(duration: nil) == 2_000_000_000)
        #expect(Conversion.transcodeBytes(duration: .nan) == 2_000_000_000)
        #expect(Conversion.enoughSpace(free: 300_000_000, duration: 100))
        #expect(!Conversion.enoughSpace(free: 299_999_999, duration: 100))
        #expect(!Conversion.enoughSpace(free: 1_000_000_000, duration: nil))
        #expect(Conversion.enoughSpace(free: nil, duration: 3600))
    }

    @Test func fractionNeedsADurationAndStaysWithinZeroAndOne() {
        #expect(Conversion.fraction(2.5, of: 10) == 0.25)
        #expect(Conversion.fraction(11, of: 10) == 1)
        #expect(Conversion.fraction(2.5, of: nil) == nil)
        #expect(Conversion.fraction(2.5, of: 0) == nil)
    }
}

@Suite struct ConversionOutcomeTests {
    @Test func onlyH264AndHevcAreRemuxed() {
        #expect(Conversion.firstStep(videoCodec: "h264") == .remux)
        #expect(Conversion.firstStep(videoCodec: "hevc") == .remux)
        #expect(Conversion.firstStep(videoCodec: "mpeg4") == .transcode)
        #expect(Conversion.firstStep(videoCodec: "vp9") == .transcode)
        #expect(Conversion.firstStep(videoCodec: "mjpeg") == .transcode)
        // Without ffprobe the remux runs, and its result's codec decides.
        #expect(Conversion.firstStep(videoCodec: nil) == .remux)
    }

    @Test func aRemuxThatPlaysIsKept() {
        #expect(Conversion.outcome(of: .remux, exitStatus: 0, result: playsWithSound, sourceHasAudio: true) == .accept)
        #expect(Conversion.outcome(of: .remux, exitStatus: 0, result: playsSilent, sourceHasAudio: false) == .accept)
    }

    @Test func aFailedUnplayableOrSoundlessRemuxIsTranscoded() {
        #expect(Conversion.outcome(of: .remux, exitStatus: 1, result: ClipProbe(), sourceHasAudio: false) == .transcode)
        #expect(Conversion.outcome(of: .remux, exitStatus: 0, result: doesNotPlay, sourceHasAudio: false) == .transcode)
        #expect(
            Conversion.outcome(
                of: .remux, exitStatus: 0, result: ClipProbe(exists: true, playable: true, hasAudio: true),
                sourceHasAudio: true) == .transcode)
        // AVFoundation drops MP3 remuxed from an AVI, so that remux plays silent.
        #expect(Conversion.outcome(of: .remux, exitStatus: 0, result: playsSilent, sourceHasAudio: true) == .transcode)
        // MPEG-4 Part 2 and MJPEG play, but only through a software decoder.
        for codec in ["mp4v", "jpeg", "hev1"] {
            var software = playsWithSound
            software.codec = codec
            #expect(Conversion.outcome(of: .remux, exitStatus: 0, result: software, sourceHasAudio: true) == .transcode)
        }
    }

    @Test func theTranscodeIsTheLastTry() {
        #expect(Conversion.outcome(of: .transcode, exitStatus: 0, result: playsSilent, sourceHasAudio: true) == .accept)
        #expect(
            Conversion.outcome(of: .transcode, exitStatus: 1, result: ClipProbe(), sourceHasAudio: false)
                == .fail(.ffmpegFailed))
        #expect(
            Conversion.outcome(of: .transcode, exitStatus: 0, result: doesNotPlay, sourceHasAudio: false)
                == .fail(.stillNotPlayable))
    }

    @Test func aToolThatNeverStartedFailsAtOnce() {
        #expect(
            Conversion.outcome(of: .remux, exitStatus: nil, result: ClipProbe(), sourceHasAudio: true)
                == .fail(.cannotStart))
    }
}

@Suite struct ConversionCandidateTests {
    @Test func blockedUnplayableClipsOnceEachInShowOrder() {
        let mkv = URL(fileURLWithPath: "/show/01_a.mkv")
        let avi = URL(fileURLWithPath: "/show/02_b.avi")
        let gone = URL(fileURLWithPath: "/show/03_c.mp4")
        let cues = [
            Cue(kind: .black, movieIndex: nil),
            Cue(kind: .clip(Clip(file: "01_a.mkv"), mkv), movieIndex: 0),
            Cue(kind: .clip(Clip(file: "02_b.avi"), avi), movieIndex: 0),
            Cue(kind: .clip(Clip(file: "03_c.mp4"), gone), movieIndex: 0),
            Cue(kind: .clip(Clip(file: "01_a.mkv"), mkv), movieIndex: 1),
        ]
        let findings = [
            Finding(severity: .block, cueIndex: 1, kind: .notPlayable),
            Finding(severity: .block, cueIndex: 2, kind: .notPlayable),
            Finding(severity: .block, cueIndex: 3, kind: .fileMissing),
            Finding(severity: .block, cueIndex: 4, kind: .notPlayable),
            Finding(severity: .block, cueIndex: 9, kind: .notPlayable),
            Finding(severity: .block, kind: .projector),
        ]
        #expect(Conversion.candidates(cues: cues, findings: findings) == [mkv, avi])
    }
}
