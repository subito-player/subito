import Foundation
import Testing

@testable import CueCore

private let t0 = Date(timeIntervalSinceReferenceDate: 0)
private let breakItem = BreakItem(minutes: 20, countdown: true, text: "Szünet")

private func clipCue(_ number: Int, movie: Int?) -> Cue {
    let url = URL(fileURLWithPath: "/show/m\(movie ?? -1)/\(number).mp4")
    return Cue(kind: .clip(Clip(file: "c.mp4", number: number), url), movieIndex: movie)
}

private func url(_ cue: Cue) -> URL {
    guard case .clip(_, let url) = cue.kind else { fatalError("not a clip cue") }
    return url
}

private let show: [Cue] = [
    Cue(kind: .black, movieIndex: nil),
    clipCue(0, movie: 0),
    clipCue(1, movie: 0),
    Cue(kind: .black, movieIndex: 0),
    Cue(kind: .breakScreen(breakItem), movieIndex: nil),
    clipCue(0, movie: 1),
    clipCue(1, movie: 1),
    Cue(kind: .logo(2), movieIndex: nil),
]

extension ShowState {
    @discardableResult
    fileprivate mutating func send(_ command: Command, at seconds: Double = 0) -> [Effect] {
        handle(command, now: t0 + seconds)
    }

    @discardableResult
    fileprivate mutating func ready(_ slot: Slot, _ index: Int, duration: Double = 100) -> [Effect] {
        send(.armedReady(slot, url(cues[index]), duration: duration))
    }

    fileprivate static func loaded(_ cues: [Cue] = show) -> ShowState {
        var state = ShowState()
        _ = state.replaceCues(cues)
        return state
    }

    fileprivate static func clip1LiveOnA() -> ShowState {
        var state = loaded()
        state.send(.arm(index: 1))
        state.ready(.a, 1)
        state.send(.go)
        return state
    }
}

@Suite struct ArmingTests {
    @Test func launchStateIsBlackMutedRehearsalWithNothingArmed() {
        let state = ShowState(cues: show)
        #expect(state.cues == show)
        #expect(state.base == .black)
        #expect(state.cover == nil)
        #expect(state.muted)
        #expect(state.mode == .rehearsal)
        #expect(state.liveIndex == nil)
        #expect(state.armedIndex == nil)
        #expect(!state.armedReady)
        #expect(!state.livePlaying)
        #expect(state.pending == nil)
    }

    @Test func clipLoadsIntoTheFreeSlotAndIsNotReadyUntilItReports() {
        let cues = [clipCue(0, movie: 0)]
        var state = ShowState()
        #expect(state.replaceCues(cues) == [.load(.a, url(cues[0]), at: 0)])
        #expect(state.armedIndex == 0)
        #expect(!state.armedReady)
        #expect(state.ready(.a, 0) == [])
        #expect(state.armedReady)

        var live = ShowState.clip1LiveOnA()
        #expect(live.send(.arm(index: 5)) == [.load(.b, url(show[5]), at: 0)])
    }

    @Test func armedSlotIsTheSlotTheArmedClipLoadsInto() {
        var state = ShowState.loaded()
        #expect(state.armedSlot == nil)
        #expect(state.send(.arm(index: 1)) == [.load(.a, url(show[1]), at: 0)])
        #expect(state.armedSlot == .a)
        state.ready(.a, 1)
        #expect(state.send(.go).last == .load(.b, url(show[2]), at: 0))
        #expect(state.armedSlot == .b)
        state.send(.arm(index: 3))
        #expect(state.armedSlot == nil)
    }

    @Test(arguments: [0, 3, 4, 7])
    func blackBreakAndLogoAreReadyImmediately(index: Int) {
        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        #expect(state.send(.arm(index: index)) == [])
        #expect(state.armedReady)
    }

    @Test func nextAndPreviousStepWithinBoundsAndResetParking() {
        var state = ShowState.loaded()
        #expect(state.send(.armPrevious) == [])
        #expect(state.armedIndex == 0)
        #expect(state.send(.armNext) == [.load(.a, url(show[1]), at: 0)])
        state.ready(.a, 1)
        state.send(.parkArmedAt(40))
        #expect(state.send(.armNext) == [.load(.a, url(show[2]), at: 0)])
        #expect(state.armedIndex == 2)
        #expect(state.armedAt == 0)
        #expect(!state.armedReady)
        state.send(.arm(index: show.count - 1))
        #expect(state.send(.armNext) == [])
        #expect(state.armedIndex == show.count - 1)
    }

    @Test func withNothingArmedNextAndPreviousStartFromTheLiveCue() {
        let cues = [clipCue(0, movie: 0), clipCue(1, movie: 0)]
        var state = ShowState.loaded(cues)
        state.ready(.a, 0)
        state.send(.go)
        state.ready(.b, 1)
        state.send(.go)
        #expect(state.armedIndex == nil)
        #expect(state.send(.armNext) == [])
        #expect(state.armedIndex == nil)
        #expect(state.send(.armPrevious) == [.load(.a, url(cues[0]), at: 0)])
        #expect(state.armedIndex == 0)
    }

    @Test func digitArmsThatClipNumberInTheArmedMovie() {
        var state = ShowState.loaded()
        #expect(state.send(.armNumber(1)) == [.load(.a, url(show[2]), at: 0)])
        state.send(.arm(index: 6))
        #expect(state.send(.armNumber(0)) == [.load(.a, url(show[5]), at: 0)])
        let before = state
        #expect(state.send(.armNumber(7)) == [])
        #expect(state == before)
    }

    @Test func digitFallsBackToTheLiveMovieWhenTheArmedCueHasNone() {
        var state = ShowState.loaded()
        state.send(.arm(index: 5))
        state.ready(.a, 5)
        state.send(.go)
        state.send(.arm(index: 7))
        #expect(state.send(.armNumber(1)) == [.load(.b, url(show[6]), at: 0)])
    }

    @Test func listClickArmsOnlyValidIndices() {
        var state = ShowState.loaded()
        let before = state
        #expect(state.send(.arm(index: -1)) == [])
        #expect(state.send(.arm(index: show.count)) == [])
        #expect(state == before)
        #expect(state.send(.arm(index: 6)) == [.load(.a, url(show[6]), at: 0)])
        #expect(state.armedIndex == 6)
    }
}

@Suite struct GoTests {
    @Test func refusedWhenNothingArmedOrClipNotReady() {
        var empty = ShowState(cues: show)
        let emptyBefore = empty
        #expect(empty.send(.go) == [.notice(.nothingArmed)])
        #expect(empty == emptyBefore)

        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        let before = state
        #expect(state.send(.go) == [.notice(.armedNotReady)])
        #expect(state == before)
    }

    @Test func clipToClipSwapsSlotsAndPreloadsTheNextIntoTheOldOne() {
        let cues = [clipCue(0, movie: 0), clipCue(1, movie: 0), clipCue(2, movie: 0)]
        var state = ShowState.loaded(cues)
        state.ready(.a, 0)
        state.send(.go)
        state.ready(.b, 1)
        #expect(state.send(.go) == [.show(.clip(.b)), .play(.b), .pause(.a), .load(.a, url(cues[2]), at: 0)])
    }

    @Test func readyClipGoesLiveClearsCoverAndArmsTheNext() {
        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        state.ready(.a, 1)
        state.send(.toggleCover(.black))
        #expect(
            state.send(.go) == [.show(.clip(.a)), .setCover(nil), .play(.a), .load(.b, url(show[2]), at: 0)])
        #expect(state.liveIndex == 1)
        #expect(state.base == .clip(.a))
        #expect(state.livePlaying)
        #expect(state.cover == nil)
        #expect(state.armedIndex == 2)
        #expect(!state.armedReady)

        state.ready(.b, 2)
        #expect(state.send(.go) == [.show(.clip(.b)), .play(.b), .pause(.a)])
        #expect(state.armedIndex == 3)
        #expect(state.armedReady)
    }

    @Test func blackBreakAndLogoEndTheLiveClip() {
        var state = ShowState.clip1LiveOnA()
        state.send(.arm(index: 3))
        state.send(.toggleCover(.logo(1)))
        #expect(state.send(.go) == [.show(.black), .setCover(nil), .pause(.a)])
        #expect(state.liveIndex == 3)
        #expect(state.base == .black)
        #expect(!state.livePlaying)
        #expect(state.cover == nil)
        #expect(
            state.send(.go, at: 10) == [
                .show(.breakScreen(breakItem, startedAt: t0 + 10)), .load(.a, url(show[5]), at: 0),
            ])
        state.send(.arm(index: 7))
        #expect(state.send(.go) == [.show(.logo(2))])
    }

    @Test func goOnTheLastCueLeavesNothingArmed() {
        var state = ShowState.loaded()
        state.send(.arm(index: show.count - 1))
        state.send(.go)
        #expect(state.armedIndex == nil)
        #expect(state.send(.go) == [.notice(.nothingArmed)])
    }
}

@Suite struct LiveClipTests {
    @Test func coverKeyTogglesAndSwapsWithoutTouchingPlayback() {
        var state = ShowState.clip1LiveOnA()
        #expect(state.send(.toggleCover(.black)) == [.setCover(.black)])
        #expect(state.send(.toggleCover(.logo(1))) == [.setCover(.logo(1))])
        #expect(state.cover == .logo(1))
        #expect(state.send(.toggleCover(.logo(1))) == [.setCover(nil)])
        #expect(state.cover == nil)
        #expect(state.livePlaying)

        state.send(.playPause)
        state.send(.toggleCover(.black))
        state.send(.toggleCover(.black))
        #expect(!state.livePlaying)
    }

    @Test func playPauseActsOnTheLiveClipEvenWhenCovered() {
        var idle = ShowState.loaded()
        #expect(idle.send(.playPause) == [])

        var state = ShowState.clip1LiveOnA()
        state.send(.toggleCover(.black))
        #expect(state.send(.playPause) == [.pause(.a)])
        #expect(!state.livePlaying)
        #expect(state.send(.playPause) == [.play(.a)])
        #expect(state.livePlaying)
    }

    @Test func endedClipHoldsItsLastFrame() {
        var state = ShowState.clip1LiveOnA()
        state.send(.liveEnded(.a))
        #expect(!state.livePlaying)
        #expect(state.send(.playPause) == [])
        #expect(state.base == .clip(.a))
    }

    @Test func seekAndRestartTargetTheLiveSlot() {
        var idle = ShowState.loaded()
        #expect(idle.send(.seekLive(by: 5)) == [])
        #expect(idle.send(.restartLive) == [])

        var state = ShowState.clip1LiveOnA()
        #expect(state.send(.seekLive(by: -30)) == [.seekBy(.a, -30)])
        #expect(state.send(.restartLive) == [.seekTo(.a, 0)])
        #expect(state.livePlaying)
    }

    @Test func restartAfterTheEndWaitsForPlay() {
        var state = ShowState.clip1LiveOnA()
        state.send(.liveEnded(.a))
        #expect(state.send(.restartLive) == [.seekTo(.a, 0)])
        #expect(!state.livePlaying)
        #expect(state.send(.playPause) == [.play(.a)])
    }

    @Test func seekingBackFromTheEndAllowsPlayAgain() {
        var state = ShowState.clip1LiveOnA()
        state.send(.liveEnded(.a))
        state.send(.seekLive(by: 5))
        #expect(state.send(.playPause) == [])
        state.send(.seekLive(by: -5))
        #expect(state.send(.playPause) == [.play(.a)])
    }
}

@Suite struct ParkTests {
    @Test func onlyAnArmedClipCanBeParked() {
        var state = ShowState.loaded()
        #expect(state.send(.parkArmed(by: 5)) == [])
        #expect(state.send(.parkArmedAt(5)) == [])
        #expect(state.armedAt == 0)
    }

    @Test func parkingBeforeReadyOnlyMovesTheTargetAndReadySeeksThere() {
        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        #expect(state.send(.parkArmed(by: -5)) == [])
        #expect(state.armedAt == 0)
        #expect(state.send(.parkArmedAt(40)) == [])
        #expect(state.send(.parkArmed(by: 5)) == [])
        #expect(state.armedAt == 45)
        #expect(state.ready(.a, 1) == [.seekTo(.a, 45)])
        #expect(state.armedReady)
    }

    @Test func readyClampsAParkPastTheEnd() {
        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        state.send(.parkArmedAt(500))
        #expect(state.ready(.a, 1, duration: 100) == [.seekTo(.a, 99.5)])
        #expect(state.armedAt == 99.5)
    }

    @Test func parkingAfterReadySeeksClampedAndGoStartsThere() {
        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        state.ready(.a, 1, duration: 100)
        #expect(state.send(.parkArmed(by: -5)) == [.seekTo(.a, 0)])
        #expect(state.send(.parkArmed(by: 130)) == [.seekTo(.a, 99.5)])
        #expect(state.send(.parkArmedAt(40)) == [.seekTo(.a, 40)])
        #expect(state.send(.parkArmed(by: -5)) == [.seekTo(.a, 35)])
        #expect(state.send(.go) == [.show(.clip(.a)), .play(.a), .load(.b, url(show[2]), at: 0)])
    }

    @Test func clipShorterThanTheMarginParksAtZero() {
        var state = ShowState.loaded()
        state.send(.arm(index: 1))
        state.ready(.a, 1, duration: 0.3)
        #expect(state.send(.parkArmedAt(5)) == [.seekTo(.a, 0)])
    }
}

@Suite struct ConfirmationTests {
    @Test func muteIsInstantButUnmuteNeedsASecondPressWithin3s() {
        var state = ShowState.loaded()
        #expect(state.send(.toggleMute) == [.notice(.confirmUnmute)])
        #expect(state.pending == .confirmUnmute)
        #expect(state.muted)
        #expect(state.send(.toggleMute, at: 2.9) == [.setMuted(false)])
        #expect(!state.muted)
        #expect(state.pending == nil)
        #expect(state.send(.toggleMute, at: 3) == [.setMuted(true)])
        #expect(state.muted)
    }

    @Test func unmuteConfirmationExpiresAfter3s() {
        var state = ShowState.loaded()
        state.send(.toggleMute)
        #expect(state.send(.toggleMute, at: 3.1) == [.notice(.confirmUnmute)])
        #expect(state.muted)
        #expect(state.send(.toggleMute, at: 4) == [.setMuted(false)])
    }

    @Test func bannerShowsOnlyWithinTheWindow() {
        var state = ShowState.loaded()
        #expect(state.activePending(at: t0) == nil)
        state.send(.requestQuit)
        #expect(state.activePending(at: t0 + 2.9) == .confirmQuit)
        #expect(state.activePending(at: t0 + 3) == nil)
        state.send(.requestQuit, at: 1)
        #expect(state.activePending(at: t0 + 1) == nil)
    }

    @Test func concertLocksSound() {
        var state = ShowState.loaded()
        state.send(.requestMode(.concert))
        state.send(.requestMode(.concert))
        #expect(state.send(.toggleMute) == [.notice(.soundLockedInConcert)])
        #expect(state.send(.toggleMute) == [.notice(.soundLockedInConcert)])
        #expect(state.muted)
    }

    @Test func modeSwitchNeedsTwoPressesAndLeavesTheOutputAlone() {
        var state = ShowState.clip1LiveOnA()
        state.send(.toggleCover(.black))
        let before = state
        #expect(state.send(.requestMode(.rehearsal)) == [])
        #expect(state == before)

        #expect(state.send(.requestMode(.concert)) == [.notice(.confirmMode(.concert))])
        #expect(state.mode == .rehearsal)
        #expect(state.send(.requestMode(.concert), at: 1) == [])
        #expect(state.mode == .concert)
        #expect(state.send(.requestMode(.rehearsal), at: 2) == [.notice(.confirmMode(.rehearsal))])
        #expect(state.send(.requestMode(.rehearsal), at: 5.5) == [.notice(.confirmMode(.rehearsal))])
        #expect(state.send(.requestMode(.rehearsal), at: 6) == [])
        #expect(state.mode == .rehearsal)
        #expect(state.muted)
        #expect(state.base == .clip(.a))
        #expect(state.cover == .black)
        #expect(state.livePlaying)
    }

    @Test func enteringConcertForcesMute() {
        var state = ShowState.loaded()
        state.send(.toggleMute)
        state.send(.toggleMute)
        state.send(.requestMode(.concert))
        #expect(state.send(.requestMode(.concert)) == [.setMuted(true)])
        #expect(state.muted)
    }

    @Test func quitNeedsASecondPressWithin3s() {
        var state = ShowState.loaded()
        #expect(state.send(.requestQuit) == [.notice(.confirmQuit)])
        #expect(state.send(.requestQuit, at: 3.5) == [.notice(.confirmQuit)])
        #expect(state.send(.requestQuit, at: 4) == [.quit])
    }

    @Test func anotherPressCancelsThePendingConfirmation() {
        var state = ShowState.clip1LiveOnA()
        state.send(.requestQuit)
        state.send(.toggleCover(.black))
        #expect(state.pending == nil)
        #expect(state.send(.requestQuit) == [.notice(.confirmQuit)])
        #expect(state.send(.toggleMute) == [.notice(.confirmUnmute)])
        #expect(state.pending == .confirmUnmute)
    }

    @Test func engineEventsDoNotCancelThePendingConfirmation() {
        var state = ShowState.clip1LiveOnA()
        state.send(.toggleMute)
        state.ready(.b, 2)
        state.send(.liveEnded(.a))
        #expect(state.send(.toggleMute) == [.setMuted(false)])
    }
}

@Suite struct StaleEventTests {
    @Test func eventsForTheWrongSlotAreIgnored() {
        var state = ShowState.clip1LiveOnA()
        #expect(state.ready(.a, 2) == [])
        #expect(!state.armedReady)
        #expect(state.send(.liveEnded(.b)) == [])
        #expect(state.livePlaying)
        #expect(state.send(.playPause) == [.pause(.a)])
    }

    @Test func lateReadyFromAReplacedArmIsIgnored() {
        var state = ShowState.loaded()
        #expect(state.send(.arm(index: 1)) == [.load(.a, url(show[1]), at: 0)])
        #expect(state.send(.arm(index: 2)) == [.load(.a, url(show[2]), at: 0)])
        #expect(state.ready(.a, 1) == [])
        #expect(!state.armedReady)
        #expect(state.send(.go) == [.notice(.armedNotReady)])
    }

    @Test func readyForASlotWhenNoClipIsArmedIsIgnored() {
        var state = ShowState.clip1LiveOnA()
        state.send(.arm(index: 3))
        let before = state
        #expect(state.ready(.b, 2) == [])
        #expect(state == before)
    }
}

@Suite struct ReplaceCuesTests {
    @Test func replacingKeepsTheOutputAndArmsTheFirstCue() {
        var state = ShowState.clip1LiveOnA()
        state.send(.toggleCover(.black))
        let other = [clipCue(3, movie: 0), Cue(kind: .black, movieIndex: nil)]
        #expect(state.replaceCues(other) == [.load(.b, url(other[0]), at: 0)])
        #expect(state.cues == other)
        #expect(state.liveIndex == nil)
        #expect(state.armedIndex == 0)
        #expect(state.base == .clip(.a))
        #expect(state.cover == .black)
        #expect(state.livePlaying)
        #expect(state.send(.seekLive(by: 5)) == [.seekBy(.a, 5)])

        #expect(state.replaceCues([]) == [])
        #expect(state.armedIndex == nil)
    }
}
