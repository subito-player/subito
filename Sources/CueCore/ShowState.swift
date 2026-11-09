import Foundation

public enum Slot: Sendable {
    case a, b
}

public enum Cover: Codable, Equatable, Sendable {
    case black
    case logo(Int)
}

public enum Base: Equatable, Sendable {
    case black
    case logo(Int)
    case breakScreen(BreakItem, startedAt: Date)
    case clip(Slot)
}

public enum Mode: String, Codable, Sendable {
    case rehearsal, concert
}

public enum Command: Equatable, Sendable {
    case go
    case playPause
    case toggleCover(Cover)
    case seekLive(by: Double)
    case restartLive
    case parkArmed(by: Double)
    case parkArmedAt(Double)
    case armNext
    case armPrevious
    case armNumber(Int)
    case arm(index: Int)
    case toggleMute
    case requestMode(Mode)
    // Concert only: press twice; switching mode or lockEditing locks it again.
    case unlockEditing
    case lockEditing
    case requestQuit
    // Concert only: the click on the quit banner after two Cmd+Q presses.
    case confirmQuitByClick
    // Also the engine's report that a park seek landed on the armed clip.
    case armedReady(Slot, URL, duration: Double)
    case liveEnded(Slot)
}

public enum Notice: Equatable, Sendable {
    case nothingArmed
    case armedNotReady
    case soundLockedInConcert
    case confirmUnmute
    case confirmMode(Mode)
    case confirmUnlock
    case confirmQuit
    case confirmQuitClick
}

public enum Effect: Equatable, Sendable {
    case load(Slot, URL, at: Double)
    case seekTo(Slot, Double)
    case seekBy(Slot, Double)
    case play(Slot)
    case pause(Slot)
    case show(Base)
    case setCover(Cover?)
    case setMuted(Bool)
    case notice(Notice)
    case quit
}

public struct ShowState: Equatable, Sendable {
    public static let confirmWindow: TimeInterval = 3
    public static let quitClickWindow: TimeInterval = 5
    public static let parkEndMargin: Double = 0.5

    public private(set) var cues: [Cue]
    public private(set) var liveIndex: Int?
    public private(set) var armedIndex: Int?
    public private(set) var armedAt: Double = 0
    public private(set) var armedReady = false
    public private(set) var base: Base = .black
    public private(set) var cover: Cover?
    public private(set) var livePlaying = false
    public private(set) var mode: Mode = .rehearsal
    public private(set) var muted = true
    public private(set) var editUnlocked = false
    public private(set) var pending: Notice?
    private var pendingUntil: Date?
    private var armedDuration: Double?
    private var liveAtEnd = false

    public init(cues: [Cue] = []) {
        self.cues = cues
    }

    public func activePending(at now: Date) -> Notice? {
        guard let pendingUntil, now < pendingUntil else { return nil }
        return pending
    }

    public var canEdit: Bool {
        mode == .rehearsal || editUnlocked
    }

    // The slot the armed clip loads into, so a preview can show that player; nil unless a clip is armed.
    public var armedSlot: Slot? {
        armedClip?.slot
    }

    // Crash recovery: the mode was confirmed before the crash, and launch is muted anyway.
    public mutating func restoreMode(_ mode: Mode) {
        self.mode = mode
    }

    public mutating func replaceCues(_ cues: [Cue]) -> [Effect] {
        self.cues = cues
        liveIndex = nil
        return arm(cues.isEmpty ? nil : 0)
    }

    // An edit never touches the output: live and armed keep their cues, base, cover and play state stay.
    public mutating func applyEdit(cues new: [Cue], indexMap: [Int?]) -> [Effect] {
        let map = { (old: Int) -> Int? in
            guard indexMap.indices.contains(old), let index = indexMap[old], new.indices.contains(index) else {
                return nil
            }
            return index
        }
        let armedURL = armedClip?.url
        let wasEmpty = cues.isEmpty
        cues = new
        liveIndex = liveIndex.flatMap(map)
        guard let old = armedIndex else {
            // Nothing armed: the cue after the live one, or the first of a show built from nothing, as GO and open do.
            if let live = liveIndex { return new.indices.contains(live + 1) ? arm(live + 1) : [] }
            return wasEmpty && !new.isEmpty ? arm(0) : []
        }
        guard let index = map(old) else {
            let next = indexMap.indices.filter { $0 > old }.lazy.compactMap(map).first
            return arm(next)
        }
        armedIndex = index
        return armedClip?.url == armedURL ? [] : arm(index)
    }

    public mutating func handle(_ command: Command, now: Date) -> [Effect] {
        // Engine events are not presses, so only expiry clears a pending confirmation for them.
        if let until = pendingUntil, now >= until || (!command.isEngineEvent && command.confirmation != pending) {
            pending = nil
            pendingUntil = nil
        }
        switch command {
        case .go:
            return go(now: now)
        case .playPause:
            guard let slot = liveSlot, !liveAtEnd else { return [] }
            livePlaying.toggle()
            return [livePlaying ? .play(slot) : .pause(slot)]
        case .toggleCover(let new):
            cover = cover == new ? nil : new
            return [.setCover(cover)]
        case .seekLive(by: let delta):
            guard let slot = liveSlot else { return [] }
            // Seeking back off the held last frame makes the clip playable again.
            if delta < 0 { liveAtEnd = false }
            return [.seekBy(slot, delta)]
        case .restartLive:
            guard let slot = liveSlot else { return [] }
            liveAtEnd = false
            return [.seekTo(slot, 0)]
        case .parkArmed(by: let delta):
            return park(at: armedAt + delta)
        case .parkArmedAt(let time):
            return park(at: time)
        case .armNext:
            return arm(ifValid: (armedIndex ?? liveIndex ?? -1) + 1)
        case .armPrevious:
            return arm(ifValid: (armedIndex ?? liveIndex ?? cues.count) - 1)
        case .armNumber(let number):
            return armClip(number: number)
        case .arm(let index):
            return arm(ifValid: index)
        case .toggleMute:
            return toggleMute(now: now)
        case .requestMode(let new):
            return requestMode(new, now: now)
        case .unlockEditing:
            guard mode == .concert, !editUnlocked else { return [] }
            guard confirm(.confirmUnlock, now: now) else { return [.notice(.confirmUnlock)] }
            editUnlocked = true
            return []
        case .lockEditing:
            editUnlocked = false
            return []
        case .requestQuit:
            guard confirm(.confirmQuit, now: now) else { return [.notice(.confirmQuit)] }
            guard mode == .concert else { return [.quit] }
            // Keys alone never end a concert: two presses, then a click on the banner.
            pending = .confirmQuitClick
            pendingUntil = now.addingTimeInterval(Self.quitClickWindow)
            return [.notice(.confirmQuitClick)]
        case .confirmQuitByClick:
            guard pending == .confirmQuitClick else { return [] }
            pending = nil
            pendingUntil = nil
            return [.quit]
        case .armedReady(let slot, let url, let duration):
            guard let armed = armedClip, armed.slot == slot, armed.url == url else { return [] }
            // After the load, a report means the latest park seek landed.
            guard armedDuration == nil else {
                armedReady = true
                return []
            }
            armedDuration = duration
            armedAt = clampArmed(armedAt)
            // GO waits for the parked frame, so it never shows frame 0 first.
            guard armedAt > 0 else {
                armedReady = true
                return []
            }
            return [.seekTo(slot, armedAt)]
        case .liveEnded(let slot):
            guard slot == liveSlot else { return [] }
            liveAtEnd = true
            livePlaying = false
            return []
        }
    }

    private var liveSlot: Slot? {
        if case .clip(let slot) = base { slot } else { nil }
    }

    private var freeSlot: Slot {
        base == .clip(.a) ? .b : .a
    }

    private var armedClip: (slot: Slot, url: URL)? {
        guard let armedIndex, case .clip(_, let url) = cues[armedIndex].kind else { return nil }
        return (freeSlot, url)
    }

    private mutating func go(now: Date) -> [Effect] {
        guard let index = armedIndex else { return [.notice(.nothingArmed)] }
        guard armedReady else { return [.notice(.armedNotReady)] }
        let next: Base
        switch cues[index].kind {
        case .clip: next = .clip(freeSlot)
        case .black: next = .black
        case .logo(let number): next = .logo(number)
        case .breakScreen(let item): next = .breakScreen(item, startedAt: now)
        }
        // Show first so an unbatched engine never flashes the old item between steps.
        var effects: [Effect] = [.show(next)]
        if cover != nil { effects.append(.setCover(nil)) }
        livePlaying = false
        if case .clip(let slot) = next {
            effects.append(.play(slot))
            livePlaying = true
        }
        if let old = liveSlot { effects.append(.pause(old)) }
        base = next
        cover = nil
        liveIndex = index
        liveAtEnd = false
        return effects + arm(index + 1 < cues.count ? index + 1 : nil)
    }

    private mutating func arm(_ index: Int?) -> [Effect] {
        armedIndex = index
        armedAt = 0
        armedDuration = nil
        guard let index else {
            armedReady = false
            return []
        }
        guard case .clip(_, let url) = cues[index].kind else {
            armedReady = true
            return []
        }
        armedReady = false
        return [.load(freeSlot, url, at: 0)]
    }

    private mutating func arm(ifValid index: Int) -> [Effect] {
        cues.indices.contains(index) ? arm(index) : []
    }

    private mutating func armClip(number: Int) -> [Effect] {
        let movie = armedIndex.flatMap { cues[$0].movieIndex } ?? liveIndex.flatMap { cues[$0].movieIndex } ?? 0
        let match = cues.firstIndex { cue in
            guard case .clip(let clip, _) = cue.kind else { return false }
            return cue.movieIndex == movie && clip.resolvedNumber == number
        }
        guard let match else { return [] }
        return arm(match)
    }

    // Before the load only the target moves; after it, GO waits until the engine reports this seek landed.
    private mutating func park(at time: Double) -> [Effect] {
        guard let armed = armedClip else { return [] }
        let target = clampArmed(time)
        // Already there: a stray Opt+Left at 0 or a click on the scrubber never makes GO wait.
        if armedReady, target == armedAt { return [] }
        armedAt = target
        guard armedDuration != nil else { return [] }
        armedReady = false
        return [.seekTo(armed.slot, armedAt)]
    }

    private func clampArmed(_ time: Double) -> Double {
        let end = armedDuration.map { max(0, $0 - Self.parkEndMargin) } ?? .infinity
        return min(max(0, time), end)
    }

    private mutating func toggleMute(now: Date) -> [Effect] {
        if mode == .concert { return [.notice(.soundLockedInConcert)] }
        if !muted {
            muted = true
            return [.setMuted(true)]
        }
        guard confirm(.confirmUnmute, now: now) else { return [.notice(.confirmUnmute)] }
        muted = false
        return [.setMuted(false)]
    }

    private mutating func requestMode(_ new: Mode, now: Date) -> [Effect] {
        guard new != mode else { return [] }
        guard confirm(.confirmMode(new), now: now) else { return [.notice(.confirmMode(new))] }
        mode = new
        editUnlocked = false
        guard new == .concert, !muted else { return [] }
        muted = true
        return [.setMuted(true)]
    }

    private mutating func confirm(_ notice: Notice, now: Date) -> Bool {
        if pending == notice {
            pending = nil
            pendingUntil = nil
            return true
        }
        pending = notice
        pendingUntil = now.addingTimeInterval(Self.confirmWindow)
        return false
    }
}

extension Command {
    fileprivate var isEngineEvent: Bool {
        switch self {
        case .armedReady, .liveEnded: true
        default: false
        }
    }

    fileprivate var confirmation: Notice? {
        switch self {
        case .toggleMute: .confirmUnmute
        case .requestMode(let mode): .confirmMode(mode)
        case .unlockEditing: .confirmUnlock
        case .requestQuit: .confirmQuit
        case .confirmQuitByClick: .confirmQuitClick
        default: nil
        }
    }
}
