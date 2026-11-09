import Foundation

public struct ClipProbe: Equatable, Sendable {
    public var exists: Bool
    public var playable: Bool
    public var width: Int
    public var height: Int
    public var fps: Double
    // FourCC, e.g. "avc1".
    public var codec: String
    public var duration: Double
    public var hasVideo: Bool
    public var hasAudio: Bool

    public init(
        exists: Bool = false,
        playable: Bool = false,
        width: Int = 0,
        height: Int = 0,
        fps: Double = 0,
        codec: String = "",
        duration: Double = 0,
        hasVideo: Bool = false,
        hasAudio: Bool = false
    ) {
        self.exists = exists
        self.playable = playable
        self.width = width
        self.height = height
        self.fps = fps
        self.codec = codec
        self.duration = duration
        self.hasVideo = hasVideo
        self.hasAudio = hasAudio
    }
}

public struct SystemProbe: Equatable, Sendable {
    public var projector: Bool
    public var projectorName: String
    public var mirrored: Bool
    // 0 when macOS does not report it.
    public var refreshHz: Double
    public var availableHz: [Double]
    public var onBattery: Bool
    public var spansDisplays: Bool
    public var soundDevice: String
    public var soundToDisplay: Bool

    public init(
        projector: Bool = true,
        projectorName: String = "",
        mirrored: Bool = false,
        refreshHz: Double = 0,
        availableHz: [Double] = [],
        onBattery: Bool = false,
        spansDisplays: Bool = false,
        soundDevice: String = "",
        soundToDisplay: Bool = false
    ) {
        self.projector = projector
        self.projectorName = projectorName
        self.mirrored = mirrored
        self.refreshHz = refreshHz
        self.availableHz = availableHz
        self.onBattery = onBattery
        self.spansDisplays = spansDisplays
        self.soundDevice = soundDevice
        self.soundToDisplay = soundToDisplay
    }
}

public enum Severity: Sendable {
    case ok, warn, block
}

public struct Finding: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case fileMissing, notPlayable, noVideo, size, frameRate, length, plannedEnd
        case logo
        case projector, mirrored, refreshRate, betterRefreshRate, power, spaces, sound
    }

    public var severity: Severity
    public var cueIndex: Int?
    public var kind: Kind
    // Numbers and file names only, so it reads the same in every language.
    public var detail: String

    public init(severity: Severity, cueIndex: Int? = nil, kind: Kind, detail: String = "") {
        self.severity = severity
        self.cueIndex = cueIndex
        self.kind = kind
        self.detail = detail
    }
}

public enum Preflight {
    public static let width = 1920
    public static let height = 1080
    public static let filmRate = 23.976
    public static let frameRateTolerance = 0.01
    // 1 s plus one frame, so the 1 s fade of an own export never warns on frame rounding.
    public static let lengthTolerance = 1.05
    // Exact film-rate multiples first, then their whole-number twins, then 60; never 120 or 165.
    public static let preferredRates: [Double] = [24000.0 / 1001, 48000.0 / 1001, 72000.0 / 1001, 24, 48, 72, 60]
    private static let rateMatch = 0.01

    public static func evaluate(clip: Clip, probe: ClipProbe) -> [Finding] {
        guard probe.exists else { return [Finding(severity: .block, kind: .fileMissing, detail: clip.file)] }
        guard probe.playable else { return [Finding(severity: .block, kind: .notPlayable, detail: clip.file)] }
        guard probe.hasVideo else { return [Finding(severity: .block, kind: .noVideo, detail: clip.file)] }
        var findings: [Finding] = []
        if probe.width != width || probe.height != height {
            findings.append(Finding(severity: .warn, kind: .size, detail: "\(probe.width)x\(probe.height)"))
        }
        if abs(probe.fps - filmRate) > frameRateTolerance {
            findings.append(Finding(severity: .warn, kind: .frameRate, detail: String(format: "%.5g fps", probe.fps)))
        }
        if let planned = clip.plannedEndS, let tail = clip.tailS,
            abs(probe.duration - (planned + tail)) > lengthTolerance
        {
            findings.append(
                Finding(severity: .warn, kind: .length, detail: "\(clock(probe.duration)) / \(clock(planned + tail))"))
        }
        if let planned = clip.plannedEndS, planned > probe.duration {
            findings.append(
                Finding(severity: .warn, kind: .plannedEnd, detail: "\(clock(planned)) / \(clock(probe.duration))"))
        }
        return findings
    }

    // A cue whose file was never probed counts as missing.
    public static func evaluate(cues: [Cue], probes: [URL: ClipProbe]) -> [Finding] {
        cues.indices.flatMap { index -> [Finding] in
            guard case .clip(let clip, let url) = cues[index].kind else { return [] }
            return evaluate(clip: clip, probe: probes[url] ?? ClipProbe()).map { finding in
                var finding = finding
                finding.cueIndex = index
                return finding
            }
        }
    }

    public static func evaluate(system probe: SystemProbe) -> [Finding] {
        var findings: [Finding] = []
        if !probe.projector {
            findings.append(Finding(severity: .block, kind: .projector))
        } else {
            let kind: Finding.Kind = probe.mirrored ? .mirrored : .projector
            findings.append(Finding(severity: probe.mirrored ? .block : .ok, kind: kind, detail: probe.projectorName))
            findings.append(refreshRate(probe))
        }
        findings.append(Finding(severity: probe.onBattery ? .warn : .ok, kind: .power))
        findings.append(Finding(severity: probe.spansDisplays ? .warn : .ok, kind: .spaces))
        findings.append(Finding(severity: probe.soundToDisplay ? .warn : .ok, kind: .sound, detail: probe.soundDevice))
        return findings
    }

    public static func recommendedRate(among available: [Double]) -> Double? {
        for preferred in preferredRates {
            if let match = available.first(where: { abs($0 - preferred) < rateMatch }) { return match }
        }
        return nil
    }

    // Informational only: the app never changes display modes.
    private static func refreshRate(_ probe: SystemProbe) -> Finding {
        var rates: [Double] = []
        for rate in probe.availableHz.sorted() where rate > 0 && !rates.contains(where: { abs($0 - rate) < rateMatch })
        {
            rates.append(rate)
        }
        let list = rates.isEmpty ? "" : " (" + rates.map(hz).joined(separator: ", ") + ")"
        guard probe.refreshHz > 0 else { return Finding(severity: .ok, kind: .refreshRate, detail: "? Hz" + list) }
        let current = hz(probe.refreshHz) + " Hz"
        if let best = recommendedRate(among: rates), abs(best - probe.refreshHz) >= rateMatch {
            return Finding(severity: .ok, kind: .betterRefreshRate, detail: "\(current) → \(hz(best)) Hz\(list)")
        }
        return Finding(severity: .ok, kind: .refreshRate, detail: current + list)
    }

    private static func hz(_ rate: Double) -> String {
        String(format: "%.5g", rate)
    }

    // m:ss.s, clamped so a NaN or a huge value can never trap Int().
    private static func clock(_ seconds: Double) -> String {
        let value = seconds.isFinite ? min(max(seconds, 0), 359_999) : 0
        let tenths = Int((value * 10).rounded())
        return String(format: "%ld:%02ld.%ld", tenths / 600, tenths / 10 % 60, tenths % 10)
    }
}
