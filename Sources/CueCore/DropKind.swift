import Foundation

public enum DropKind: Equatable, Sendable {
    case files
    case row
    case none

    // SwiftUI's itemProviders(for:) also hands back providers that don't really carry the type, so decide by registration.
    public static func classify(_ providers: [[String]]) -> DropKind {
        if providers.contains(where: { $0.contains("public.file-url") }) { return .files }
        if providers.contains(where: { $0.contains("public.utf8-plain-text") }) { return .row }
        return .none
    }
}

public enum DroppedFile: Equatable, Sendable {
    case clip
    case movie
    case none

    // Any .json goes the movie way, so a dropped concert file gets its "can't add a concert" notice.
    public static func classify(_ url: URL, isFolder: Bool, isVideo: Bool) -> DroppedFile {
        if isFolder || url.pathExtension.lowercased() == "json" { return .movie }
        return isVideo ? .clip : .none
    }
}
