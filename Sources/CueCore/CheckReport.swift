import Foundation

// The `--check` result: one JSON object for scripts, English only.
public struct CheckReport: Codable, Equatable, Sendable {
    public enum Result: String, Codable, Sendable {
        case ok, warnings, blocked
        // The show itself could not be loaded.
        case error
    }

    public struct Entry: Codable, Equatable, Sendable {
        public var severity: String
        // 0-based index into the flattened cue list; nil for show-level findings.
        public var cue: Int?
        public var number: String?
        // The cue's title, or the show's for a show-level finding.
        public var title: String
        public var kind: String
        public var detail: String

        private enum CodingKeys: String, CodingKey {
            case severity, cue, number, title, kind, detail
        }

        // Optionals are written as null, so every entry has the same keys.
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(severity, forKey: .severity)
            try container.encode(cue, forKey: .cue)
            try container.encode(number, forKey: .number)
            try container.encode(title, forKey: .title)
            try container.encode(kind, forKey: .kind)
            try container.encode(detail, forKey: .detail)
        }
    }

    public var show: String
    public var title: String
    public var cueCount: Int
    public var findings: [Entry]
    public var result: Result
    public var error: String?

    private enum CodingKeys: String, CodingKey {
        case show, title, findings, result, error
        case cueCount = "cues"
    }

    // Findings of severity ok are not reported; a show without cues is never ok.
    public init(show: String, title: String, cues: [Cue], findings: [Finding]) {
        let empty = cues.isEmpty ? [Finding(severity: .warn, kind: .emptyShow)] : []
        let reported = empty + findings.filter { $0.severity != .ok }
        self.show = show
        self.title = title
        cueCount = cues.count
        self.findings = reported.map { finding in
            let cue = finding.cueIndex.flatMap { cues.indices.contains($0) ? $0 : nil }
            let described = cue.map { Self.describe(cues[$0]) } ?? (number: nil, title: title)
            return Entry(
                severity: finding.severity.rawValue, cue: cue, number: described.number, title: described.title,
                kind: finding.kind.rawValue, detail: finding.detail)
        }
        result = reported.contains { $0.severity == .block } ? .blocked : reported.isEmpty ? .ok : .warnings
        error = nil
    }

    public init(show: String, error: String) {
        self.show = show
        title = ""
        cueCount = 0
        findings = []
        result = .error
        self.error = error
    }

    public var exitCode: Int32 {
        switch result {
        case .ok: 0
        case .warnings: 1
        case .blocked: 2
        case .error: 3
        }
    }

    public func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(self)
        data.append(0x0A)
        return data
    }

    private static func describe(_ cue: Cue) -> (number: String?, title: String) {
        switch cue.kind {
        case .clip(let clip, _): (clip.resolvedNumber.map { String(format: "%02ld", $0) }, clip.resolvedTitle)
        case .black: (nil, "Black")
        case .breakScreen(let item): (nil, item.text ?? "Break")
        case .logo(let number): (nil, "Logo \(number)")
        }
    }
}
