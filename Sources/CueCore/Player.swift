import Foundation

@MainActor
public protocol Player: AnyObject {
    func load(_ slot: Slot, url: URL, at time: Double)
    func seek(_ slot: Slot, to time: Double)
    func seek(_ slot: Slot, by delta: Double)
    func play(_ slot: Slot)
    func pause(_ slot: Slot)
    func show(_ base: Base)
    func setCover(_ cover: Cover?)
    func setMuted(_ muted: Bool)
}

extension Player {
    public func perform(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .load(let slot, let url, let time): load(slot, url: url, at: time)
            case .seekTo(let slot, let time): seek(slot, to: time)
            case .seekBy(let slot, let delta): seek(slot, by: delta)
            case .play(let slot): play(slot)
            case .pause(let slot): pause(slot)
            case .show(let base): show(base)
            case .setCover(let cover): setCover(cover)
            case .setMuted(let muted): setMuted(muted)
            case .notice, .quit: continue
            }
        }
    }
}
