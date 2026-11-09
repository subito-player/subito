import Testing

@testable import CueCore

@Suite struct CheckCommandTests {
    @Test func withoutDoubleDashOptionsTheAppStarts() {
        #expect(CheckCommand.parse([]) == .app)
        #expect(CheckCommand.parse(["/shows/gala.concert.json"]) == .app)
        #expect(CheckCommand.parse(["-psn_0_123"]) == .app)
        #expect(CheckCommand.parse(["-AppleLanguages", "(hu)"]) == .app)
        #expect(CheckCommand.parse(["-NSDocumentRevisionsDebugMode", "YES"]) == .app)
    }

    @Test func checkTakesExactlyOnePath() {
        #expect(
            CheckCommand.parse(["--check", "/shows/gala.concert.json"]) == .check(path: "/shows/gala.concert.json"))
        #expect(CheckCommand.parse(["--check", "clips"]) == .check(path: "clips"))
    }

    @Test(arguments: [
        ["--check"], ["--check", ""], ["--check", "a", "b"], ["--check", "--check"], ["--chek", "a"], ["--help"],
        ["a", "--check"], ["-NSFoo", "YES", "--check", "a"],
    ])
    func anythingElseWithADoubleDashIsUsage(arguments: [String]) {
        #expect(CheckCommand.parse(arguments) == .usage)
    }

    @Test func usageNamesTheProgramAndTheExitCodes() {
        let text = CheckCommand.usage(program: "tool")
        #expect(text.hasPrefix("usage: tool --check"))
        #expect(text.contains("exit 0 ok, 1 warnings, 2 blocked, 3"))
        #expect(text.hasSuffix("\n") && !text.hasSuffix("\n\n"))
    }
}
