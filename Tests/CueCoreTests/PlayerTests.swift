import Foundation
import Testing

@testable import CueCore

@MainActor
private final class RecordingPlayer: Player {
    var calls: [Effect] = []

    func load(_ slot: Slot, url: URL, at time: Double) { calls.append(.load(slot, url, at: time)) }
    func seek(_ slot: Slot, to time: Double) { calls.append(.seekTo(slot, time)) }
    func seek(_ slot: Slot, by delta: Double) { calls.append(.seekBy(slot, delta)) }
    func play(_ slot: Slot) { calls.append(.play(slot)) }
    func pause(_ slot: Slot) { calls.append(.pause(slot)) }
    func show(_ base: Base) { calls.append(.show(base)) }
    func setCover(_ cover: Cover?) { calls.append(.setCover(cover)) }
    func setMuted(_ muted: Bool) { calls.append(.setMuted(muted)) }
}

@Suite @MainActor struct PlayerTests {
    @Test func performDispatchesPlaybackInOrderAndSkipsUIEffects() {
        let url = URL(fileURLWithPath: "/show/1.mp4")
        let playback: [Effect] = [
            .setCover(nil), .show(.clip(.b)), .play(.b), .pause(.a), .load(.a, url, at: 12), .seekTo(.a, 30),
            .seekBy(.b, -5), .setMuted(false),
        ]
        let player = RecordingPlayer()
        player.perform([.notice(.confirmQuit)] + playback[..<4] + [.quit] + playback[4...])
        #expect(player.calls == playback)
    }
}
