import Testing

@testable import CueCore

@Suite struct LaunchArgumentsTests {
    @Test func aPlainPathIsTheShow() {
        #expect(LaunchArguments.showPath(["/shows/gala.concert.json"]) == "/shows/gala.concert.json")
        #expect(LaunchArguments.showPath(["/shows/gala.concert.json", "extra"]) == "/shows/gala.concert.json")
    }

    @Test func noArgumentsMeanNoShow() {
        #expect(LaunchArguments.showPath([]) == nil)
    }

    @Test(arguments: [
        ["-psn_0_123"], ["-AppleLanguages", "(hu)"], ["-NSDocumentRevisionsDebugMode", "YES"],
        ["-psn_0_123", "-AppleLanguages", "(hu)"], ["-NSDocumentRevisionsDebugMode"],
    ])
    func injectedFlagsAndTheirValuesAreNeverTheShow(arguments: [String]) {
        #expect(LaunchArguments.showPath(arguments) == nil)
    }

    @Test func aRealPathAfterInjectedFlagsStillWins() {
        #expect(LaunchArguments.showPath(["-psn_0_123", "/shows/a"]) == "/shows/a")
        #expect(LaunchArguments.showPath(["-AppleLanguages", "(hu)", "/shows/a"]) == "/shows/a")
        let all = ["-psn_0_123", "-NSDocumentRevisionsDebugMode", "YES", "-AppleLanguages", "(hu)", "/shows/a"]
        #expect(LaunchArguments.showPath(all) == "/shows/a")
    }
}
