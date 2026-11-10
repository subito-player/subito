import CueCore
import Foundation
import Testing

struct DropKindTests {
    @Test func aRowDragIsNeverTakenForFinderFiles() {
        #expect(DropKind.classify([["public.utf8-plain-text"]]) == .row)
    }

    @Test func finderFilesWinEvenWhenTheyAlsoCarryText() {
        #expect(DropKind.classify([["public.file-url", "public.utf8-plain-text"]]) == .files)
        #expect(DropKind.classify([["public.utf8-plain-text"], ["public.file-url"]]) == .files)
    }

    @Test func anythingElseIsIgnored() {
        #expect(DropKind.classify([]) == .none)
        #expect(DropKind.classify([["public.png"]]) == .none)
    }

    @Test func aDroppedMovieFileOrClipFolderBecomesAMovieNotNothing() {
        let movie = URL(fileURLWithPath: "/m/The Greatest Showman.movie.json")
        #expect(DroppedFile.classify(movie, isFolder: false, isVideo: false) == .movie)
        #expect(DroppedFile.classify(URL(fileURLWithPath: "/m/Showman"), isFolder: true, isVideo: false) == .movie)
        #expect(DroppedFile.classify(URL(fileURLWithPath: "/m/01_a.mp4"), isFolder: false, isVideo: true) == .clip)
        #expect(DroppedFile.classify(URL(fileURLWithPath: "/m/logo.png"), isFolder: false, isVideo: false) == .none)
    }
}
