import Foundation

// ffmpeg is found at run time, never linked; a remux first, a hardware H.264 transcode only when that does not play.
public enum Conversion {
    public enum Step: String, Sendable {
        case remux, transcode
    }

    public enum Failure: Equatable, Sendable {
        case cannotStart
        case ffmpegFailed
        case stillNotPlayable
        case cannotSave
        case ffmpegMissing
        case diskFull
    }

    public enum Outcome: Equatable, Sendable {
        case accept
        case transcode
        case fail(Failure)
    }

    public struct Invocation: Equatable, Sendable {
        public var executable: String
        public var arguments: [String]

        public init(executable: String, arguments: [String]) {
            self.executable = executable
            self.arguments = arguments
        }
    }

    public struct Binaries: Equatable, Sendable {
        public var ffmpeg: String
        public var ffprobe: String?

        public init(ffmpeg: String, ffprobe: String? = nil) {
            self.ffmpeg = ffmpeg
            self.ffprobe = ffprobe
        }
    }

    public enum Tool: Equatable, Sendable {
        case installed(Binaries)
        // Resolved once per session to store paths; the first resolution may download ffmpeg.
        case nix(String)
    }

    public struct SourceInfo: Equatable, Sendable {
        public var videoCodec: String?
        public var hasAudio: Bool
        public var duration: Double?

        public init(videoCodec: String? = nil, hasAudio: Bool = false, duration: Double? = nil) {
            self.videoCodec = videoCodec
            self.hasAudio = hasAudio
            self.duration = duration
        }
    }

    public static func ffmpegPaths(home: String, user: String) -> [String] {
        [
            "/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", home + "/.nix-profile/bin/ffmpeg",
            "/etc/profiles/per-user/\(user)/bin/ffmpeg", "/run/current-system/sw/bin/ffmpeg",
        ]
    }

    public static func nixPaths(home: String, user: String) -> [String] {
        [
            "/nix/var/nix/profiles/default/bin/nix", "/run/current-system/sw/bin/nix", home + "/.nix-profile/bin/nix",
            "/etc/profiles/per-user/\(user)/bin/nix",
        ]
    }

    // An installed ffmpeg wins; ffprobe counts only right next to it.
    public static func locate(ffmpeg: [String], nix: [String], exists: (String) -> Bool) -> Tool? {
        if let path = ffmpeg.first(where: exists) {
            let probe = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("ffprobe").path
            return .installed(Binaries(ffmpeg: path, ffprobe: exists(probe) ? probe : nil))
        }
        return nix.first(where: exists).map(Tool.nix)
    }

    // Explicit features, so a Nix without flakes switched on in its config still runs it.
    public static func resolveInvocation(nix: String, offline: Bool) -> Invocation {
        Invocation(
            executable: nix,
            arguments: ["--extra-experimental-features", "nix-command flakes", "shell"] + (offline ? ["--offline"] : [])
                + ["nixpkgs#ffmpeg", "--command", "/bin/sh", "-c", "command -v ffmpeg; command -v ffprobe"])
    }

    public static func binaries(fromResolveOutput output: String) -> Binaries? {
        let lines = output.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
        let path = { (name: String) in lines.first { $0.hasPrefix("/") && $0.hasSuffix("/" + name) } }
        return path("ffmpeg").map { Binaries(ffmpeg: $0, ffprobe: path("ffprobe")) }
    }

    // Only a child the converter started: by name, and not started after its pid was written down.
    public static func isOrphan(name: String?, startedAt: Date?, pidWrittenAt: Date?) -> Bool {
        guard let name, ["ffmpeg", "ffprobe", "nix"].contains(name) else { return false }
        guard let startedAt, let pidWrittenAt else { return true }
        return startedAt.timeIntervalSince(pidWrittenAt) < 2
    }

    // The clip of a blocked "cannot play" finding: the file is there, AVFoundation just cannot open it.
    public static func candidate(_ finding: Finding, cues: [Cue]) -> URL? {
        guard finding.kind == .notPlayable, let index = finding.cueIndex, cues.indices.contains(index),
            case .clip(_, let url) = cues[index].kind
        else { return nil }
        return url
    }

    // Once each, in show order.
    public static func candidates(cues: [Cue], findings: [Finding]) -> [URL] {
        var urls: [URL] = []
        for url in findings.compactMap({ candidate($0, cues: cues) }) where !urls.contains(url) {
            urls.append(url)
        }
        return urls
    }

    // Next to the original, which is never overwritten or touched.
    public static func outputURL(for source: URL, exists: (URL) -> Bool) -> URL {
        let folder = source.deletingLastPathComponent()
        let stem = source.deletingPathExtension().lastPathComponent
        var candidate = folder.appendingPathComponent(stem + ".mp4")
        var count = 1
        while exists(candidate) {
            let suffix = count == 1 ? "converted" : "converted \(count)"
            candidate = folder.appendingPathComponent("\(stem) (\(suffix)).mp4")
            count += 1
        }
        return candidate
    }

    // Hidden and without an NN_ prefix, so neither Finder nor "Open folder" offers a half-written file.
    public static func tempURL(for source: URL) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return source.deletingLastPathComponent().appendingPathComponent(".\(stem).converting.mp4")
    }

    public static func probeArguments(_ input: URL) -> [String] {
        ["-v", "error", "-show_entries", "stream=codec_type,codec_name:format=duration", "-of", "json", input.path]
    }

    public static func sourceInfo(json: Data) -> SourceInfo? {
        struct Output: Decodable {
            struct Stream: Decodable {
                var codecType: String?
                var codecName: String?
            }
            struct Format: Decodable {
                var duration: String?
            }
            var streams: [Stream]?
            var format: Format?
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let output = try? decoder.decode(Output.self, from: json) else { return nil }
        let streams = output.streams ?? []
        let duration = output.format?.duration.flatMap(Double.init).flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        return SourceInfo(
            videoCodec: streams.first { $0.codecType == "video" }?.codecName,
            hasAudio: streams.contains { $0.codecType == "audio" }, duration: duration)
    }

    // Progress on stdout, errors only on stderr; -nostdin so ffmpeg never waits for a key.
    public static func arguments(_ step: Step, input: URL, output: URL, hevc: Bool) -> [String] {
        let head = [
            "-hide_banner", "-nostdin", "-loglevel", "error", "-nostats", "-progress", "pipe:1", "-n", "-i", input.path,
            "-map", "0:v:0", "-map", "0:a?",
        ]
        let codecs: [String]
        switch step {
        case .remux:
            // AVFoundation plays HEVC in MP4 only under the hvc1 tag.
            codecs = ["-c", "copy"] + (hevc ? ["-tag:v", "hvc1"] : [])
        case .transcode:
            codecs = ["-c:v", "h264_videotoolbox", "-b:v", "20M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "192k"]
        }
        return head + codecs + ["-movflags", "+faststart", "-f", "mp4", output.path]
    }

    // `-progress` writes key=value lines; out_time_us is the output position in microseconds.
    public static func progressSeconds(_ line: String) -> Double? {
        let key = "out_time_us="
        guard line.hasPrefix(key), let micros = Double(line.dropFirst(key.count)), micros.isFinite, micros >= 0 else {
            return nil
        }
        return micros / 1_000_000
    }

    public static func fraction(_ seconds: Double, of duration: Double?) -> Double? {
        guard let duration, duration > 0, seconds.isFinite else { return nil }
        return min(max(seconds / duration, 0), 1)
    }

    // Only H.264 and HEVC are remuxed: any other picture would be decoded in software on stage.
    public static func firstStep(videoCodec: String?) -> Step {
        guard let videoCodec else { return .remux }
        return ["h264", "hevc"].contains(videoCodec) ? .remux : .transcode
    }

    // 20 Mbit/s plus a fifth for audio and the container; 2 GB when the length is unknown.
    public static func transcodeBytes(duration: Double?) -> Int64 {
        guard let duration, duration.isFinite, duration > 0 else { return 2_000_000_000 }
        return Int64((duration * 20_000_000 / 8 * 1.2).rounded(.up))
    }

    // An unknown free space never blocks.
    public static func enoughSpace(free: Int64?, duration: Double?) -> Bool {
        guard let free else { return true }
        return free >= transcodeBytes(duration: duration)
    }

    // exitStatus nil: the tool never started. A remux is kept only as H.264 or HEVC with the source's audio.
    public static func outcome(of step: Step, exitStatus: Int32?, result: ClipProbe, sourceHasAudio: Bool) -> Outcome {
        guard let exitStatus else { return .fail(.cannotStart) }
        let plays = exitStatus == 0 && result.playable && result.hasVideo
        switch step {
        case .remux:
            let hardware = ["avc1", "hvc1"].contains(result.codec)
            return plays && hardware && (result.hasAudio || !sourceHasAudio) ? .accept : .transcode
        case .transcode:
            guard exitStatus == 0 else { return .fail(.ffmpegFailed) }
            return plays ? .accept : .fail(.stillNotPlayable)
        }
    }
}
