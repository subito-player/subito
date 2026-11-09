import Testing

@testable import CueCore

@Suite struct OutputPresentationTests {
    @Test(arguments: OutputPresentation.allCases)
    func concertIsAlwaysFullscreen(requested: OutputPresentation) {
        #expect(OutputPresentation.effective(requested: requested, mode: .concert) == .fullscreen)
    }

    @Test(arguments: OutputPresentation.allCases)
    func rehearsalShowsWhatWasPicked(requested: OutputPresentation) {
        #expect(OutputPresentation.effective(requested: requested, mode: .rehearsal) == requested)
    }
}
