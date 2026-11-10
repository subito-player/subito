import Foundation
import Testing

@testable import CueCore

@Suite struct UpdateTests {
    private func version(_ text: String) throws -> AppVersion {
        try #require(AppVersion(text))
    }

    private func payload(
        tag: String = "v0.3.1", draft: Bool = false, prerelease: Bool = false,
        page: String = "https://github.com/subito-player/subito/releases/tag/v0.3.1",
        assets: [(String, String)] = [
            ("Subito-0.3.1.zip", "https://github.com/subito-player/subito/releases/download/v0.3.1/Subito-0.3.1.zip"),
            ("Subito-0.3.1.dmg", "https://github.com/subito-player/subito/releases/download/v0.3.1/Subito-0.3.1.dmg"),
        ]
    ) -> Data {
        let list = assets.map { "{\"name\": \"\($0.0)\", \"browser_download_url\": \"\($0.1)\"}" }
        return Data(
            """
            {"tag_name": "\(tag)", "draft": \(draft), "prerelease": \(prerelease), "html_url": "\(page)",
             "assets": [\(list.joined(separator: ","))]}
            """.utf8)
    }

    @Test func aTagWithOrWithoutTheVIsTheSameVersion() throws {
        #expect(try version("v0.3.1") == version("0.3.1"))
        #expect(try version("v0.3.1").description == "0.3.1")
    }

    @Test func partsCompareAsNumbersNotText() throws {
        #expect(try version("v0.3.1") > version("0.3.0"))
        #expect(try version("0.10.0") > version("0.9.1"))
        #expect(try version("1.0.0") > version("0.99.99"))
    }

    @Test func aMissingPartCountsAsZero() throws {
        #expect(try version("0.3") == version("0.3.0"))
        #expect(try version("0.3.0") < version("0.3.0.1"))
    }

    @Test(arguments: [
        "", "v", "nightly", "0.3.0-rc1", "0.3.x", "1..2", "v0.3.", " 0.3.0", "+1.2", "-1", "99999999999999999999",
    ])
    func aTagThatIsNoVersionIsIgnored(text: String) {
        #expect(AppVersion(text) == nil)
    }

    @Test func theDiskImageIsPickedOverOtherAssets() throws {
        let release = try Update.release(from: payload())
        #expect(release.version == (try version("0.3.1")))
        #expect(release.downloadURL?.lastPathComponent == "Subito-0.3.1.dmg")
        #expect(release.pageURL.lastPathComponent == "v0.3.1")
    }

    @Test func noDiskImageFallsBackToTheReleasePage() throws {
        let zip = ("Subito-0.3.1.zip", "https://github.com/subito-player/subito/releases/download/v0.3.1/a.zip")
        let release = try Update.release(from: payload(assets: [zip]))
        #expect(release.downloadURL == nil)
        #expect(
            Update.verdict(running: try version("0.3.0"), latest: release)
                == .available(release.version, release.pageURL))
    }

    @Test func aDraftOrPrereleaseOrBadTagIsIgnored() {
        #expect(throws: Update.Failure.noRelease) { try Update.release(from: payload(draft: true)) }
        #expect(throws: Update.Failure.noRelease) { try Update.release(from: payload(prerelease: true)) }
        #expect(throws: Update.Failure.noRelease) { try Update.release(from: payload(tag: "nightly")) }
    }

    @Test(arguments: ["", "not json", "[]", "{}", "{\"tag_name\": \"v0.3.1\"}"])
    func anAnswerThatIsNotAReleaseIsAFailureNotACrash(body: String) {
        #expect(throws: Update.Failure.malformed) { try Update.release(from: Data(body.utf8)) }
    }

    @Test func onlyHTTPSLinksAreKept() {
        #expect(throws: Update.Failure.malformed) {
            try Update.release(from: payload(page: "file:///Applications/Utilities/Terminal.app"))
        }
        #expect(throws: Update.Failure.malformed) {
            try Update.release(from: payload(assets: [("Subito.dmg", "http://example.com/Subito.dmg")]))
        }
    }

    @Test func aNewerReleaseIsAvailableWithItsDownload() throws {
        let release = try Update.release(from: payload())
        let verdict = Update.verdict(running: try version("0.3.0"), latest: release)
        #expect(verdict == .available(release.version, try #require(release.downloadURL)))
    }

    @Test func theSameOrAnOlderReleaseIsUpToDate() throws {
        let release = try Update.release(from: payload())
        #expect(Update.verdict(running: try version("0.3.1"), latest: release) == .upToDate)
        #expect(Update.verdict(running: try version("0.4.0"), latest: release) == .upToDate)
    }
}
