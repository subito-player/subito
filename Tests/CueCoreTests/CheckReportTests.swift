import Foundation
import Testing

@testable import CueCore

private let clipURL = URL(fileURLWithPath: "/show/05_finale.mp4")
private let cues = [
    Cue(kind: .black, movieIndex: nil),
    Cue(kind: .clip(Clip(file: "05_finale.mp4"), clipURL), movieIndex: 0),
]
private let warning = Finding(severity: .warn, cueIndex: 1, kind: .frameRate, detail: "25 fps")
private let block = Finding(severity: .block, cueIndex: 1, kind: .notPlayable, detail: "05_finale.mp4")
private let showLevel = Finding(severity: .warn, kind: .logo, detail: "1 · orchestra.png")

private func report(_ findings: [Finding]) -> CheckReport {
    CheckReport(show: "gala.concert.json", title: "Gala", cues: cues, findings: findings)
}

private func object(_ report: CheckReport) throws -> [String: Any] {
    try #require(try JSONSerialization.jsonObject(with: report.json()) as? [String: Any])
}

@Suite struct CheckResultTests {
    @Test func noFindingsOrOnlyOkOnesIsOkAndExitsZero() {
        for findings in [[], [Finding(severity: .ok, kind: .power)]] {
            let report = report(findings)
            #expect(report.result == .ok)
            #expect(report.exitCode == 0)
            #expect(report.findings.isEmpty)
        }
    }

    @Test func aShowWithoutCuesWarnsInsteadOfBeingOk() throws {
        let empty = CheckReport(show: "gala.concert.json", title: "Gala", cues: [], findings: [])
        #expect(empty.result == .warnings)
        #expect(empty.exitCode == 1)
        let entry = try #require(empty.findings.first)
        #expect(empty.findings.count == 1)
        #expect(entry.kind == "emptyShow")
        #expect(entry.severity == "warn")
        #expect(entry.cue == nil)
        #expect(entry.title == "Gala")
    }

    @Test func warningsOnlyExitOne() {
        let report = report([warning, showLevel])
        #expect(report.result == .warnings)
        #expect(report.exitCode == 1)
        #expect(report.findings.count == 2)
    }

    @Test func anyBlockExitsTwoEvenAmongWarnings() {
        let report = report([warning, block])
        #expect(report.result == .blocked)
        #expect(report.exitCode == 2)
    }

    @Test func aShowThatCannotLoadExitsThreeWithTheError() throws {
        let report = CheckReport(show: "gone.concert.json", error: "Cannot read gone.concert.json")
        #expect(report.result == .error)
        #expect(report.exitCode == 3)
        let json = try object(report)
        #expect(json["error"] as? String == "Cannot read gone.concert.json")
        #expect(json["result"] as? String == "error")
        #expect((json["findings"] as? [Any])?.isEmpty == true)
    }
}

@Suite struct CheckJSONTests {
    @Test func topLevelKeysAndCueCount() throws {
        let json = try object(report([warning]))
        #expect(Set(json.keys) == ["show", "title", "cues", "findings", "result"])
        #expect(json["show"] as? String == "gala.concert.json")
        #expect(json["title"] as? String == "Gala")
        #expect(json["cues"] as? Int == 2)
        #expect(json["result"] as? String == "warnings")
    }

    @Test func aCueFindingNamesItsCueNumberAndTitle() throws {
        let entries = try #require(try object(report([block]))["findings"] as? [[String: Any]])
        let entry = try #require(entries.first)
        #expect(Set(entry.keys) == ["severity", "cue", "number", "title", "kind", "detail"])
        #expect(entry["severity"] as? String == "block")
        #expect(entry["cue"] as? Int == 1)
        #expect(entry["number"] as? String == "05")
        #expect(entry["title"] as? String == "Finale")
        #expect(entry["kind"] as? String == "notPlayable")
        #expect(entry["detail"] as? String == "05_finale.mp4")
    }

    @Test func aShowLevelFindingHasNullCueAndNumberAndTheShowTitle() throws {
        let entries = try #require(try object(report([showLevel]))["findings"] as? [[String: Any]])
        let entry = try #require(entries.first)
        #expect(entry["cue"] is NSNull)
        #expect(entry["number"] is NSNull)
        #expect(entry["title"] as? String == "Gala")
        #expect(entry["kind"] as? String == "logo")
    }

    @Test func aCueWithoutANumberAndAnUnknownCueIndexStayNull() throws {
        let logoCue = Cue(kind: .logo(3), movieIndex: nil)
        let findings = [
            Finding(severity: .warn, cueIndex: 0, kind: .logoNumber, detail: "3"),
            Finding(severity: .warn, cueIndex: 9, kind: .logoNumber, detail: "9"),
        ]
        let report = CheckReport(show: "x", title: "Gala", cues: [logoCue], findings: findings)
        let entries = try #require(try object(report)["findings"] as? [[String: Any]])
        #expect(entries[0]["cue"] as? Int == 0)
        #expect(entries[0]["number"] is NSNull)
        #expect(entries[0]["title"] as? String == "Logo 3")
        #expect(entries[1]["cue"] is NSNull)
    }

    @Test func prettyPrintedSortedKeysSlashesIntactOneTrailingNewline() throws {
        let report = CheckReport(show: "/shows/gala.concert.json", title: "Gala", cues: cues, findings: [warning])
        let text = try #require(String(data: report.json(), encoding: .utf8))
        #expect(text.contains("\"/shows/gala.concert.json\""))
        // Top-level keys sit at two spaces of indent.
        let topLevel = text.split(separator: "\n").filter { $0.hasPrefix("  \"") }.map {
            $0.dropFirst(3).prefix { $0 != "\"" }
        }
        #expect(topLevel == ["cues", "findings", "result", "show", "title"])
        #expect(text.hasSuffix("}\n") && !text.hasSuffix("\n\n"))
    }
}
