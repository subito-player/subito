import Foundation
import Testing

@testable import CueCore

@Suite struct TextTailTests {
    @Test func shortFileGivesEveryLine() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("today.log")
            try write("a\nb\nc\n", to: url)
            #expect(TextTail.lastLines(of: url, count: 200) == ["a", "b", "c"])
        }
    }

    @Test func longFileGivesTheLastLinesOnly() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("today.log")
            try write((1...500).map { "line \($0)" }.joined(separator: "\n") + "\n", to: url)
            let tail = TextTail.lastLines(of: url, count: 200)
            #expect(tail.count == 200)
            #expect(tail.first == "line 301")
            #expect(tail.last == "line 500")
        }
    }

    @Test func aReadFromTheMiddleDropsTheCutLine() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("today.log")
            try write("first line\nsecond line\nthird", to: url)
            #expect(TextTail.lastLines(of: url, count: 200, maxBytes: 14) == ["third"])
        }
    }

    @Test func missingFileGivesNothing() throws {
        try withTempDir { dir in
            #expect(TextTail.lastLines(of: dir.appendingPathComponent("none.log"), count: 200) == [])
        }
    }
}
