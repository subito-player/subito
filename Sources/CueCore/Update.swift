import Foundation

// Dotted numbers, "0.3.1" or a release tag "v0.3.1"; anything else (a suffix, an empty part) is no version.
public struct AppVersion: Comparable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let digits = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let numbers = digits.split(separator: ".", omittingEmptySubsequences: false)
            .map { part in part.allSatisfy { ("0"..."9").contains($0) } ? Int(part) : nil }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        parts = numbers.compactMap { $0 }
    }

    public var description: String {
        parts.map(String.init).joined(separator: ".")
    }

    // A missing part counts as 0, so "0.3" and "0.3.0" are the same version.
    public static func < (a: AppVersion, b: AppVersion) -> Bool {
        for index in 0..<max(a.parts.count, b.parts.count) {
            let x = index < a.parts.count ? a.parts[index] : 0
            let y = index < b.parts.count ? b.parts[index] : 0
            if x != y { return x < y }
        }
        return false
    }

    public static func == (a: AppVersion, b: AppVersion) -> Bool {
        !(a < b) && !(b < a)
    }
}

// What the app asks GitHub for and what it does with the answer; it never downloads or installs anything.
public enum Update {
    public struct Release: Equatable, Sendable {
        public var version: AppVersion
        public var pageURL: URL
        public var downloadURL: URL?
    }

    public enum Failure: Error, Equatable, Sendable {
        // This build has no version or no update repository (not run from the .app).
        case notConfigured
        case network
        case http(Int)
        case malformed
        // A draft, a prerelease or a tag that is no version.
        case noRelease
    }

    public enum Verdict: Equatable, Sendable {
        case upToDate
        // The .dmg download, else the release page.
        case available(AppVersion, URL)
    }

    private struct Payload: Decodable {
        struct Asset: Decodable {
            var name: String
            var url: URL

            enum CodingKeys: String, CodingKey {
                case name
                case url = "browser_download_url"
            }
        }

        var tag: String
        var page: URL
        var draft: Bool?
        var prerelease: Bool?
        var assets: [Asset]?

        enum CodingKeys: String, CodingKey {
            case tag = "tag_name"
            case page = "html_url"
            case draft, prerelease, assets
        }
    }

    // The body of GET /repos/<owner>/<name>/releases/latest.
    public static func release(from data: Data) throws -> Release {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else { throw Failure.malformed }
        guard payload.draft != true, payload.prerelease != true, let version = AppVersion(payload.tag) else {
            throw Failure.noRelease
        }
        let download = payload.assets?.first { $0.name.lowercased().hasSuffix(".dmg") }?.url
        // These URLs get opened in the browser, so nothing but https is taken from the answer.
        guard payload.page.scheme == "https", download.map({ $0.scheme == "https" }) ?? true else {
            throw Failure.malformed
        }
        return Release(version: version, pageURL: payload.page, downloadURL: download)
    }

    public static func verdict(running: AppVersion, latest: Release) -> Verdict {
        latest.version > running ? .available(latest.version, latest.downloadURL ?? latest.pageURL) : .upToDate
    }
}
