import CueCore
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
}
