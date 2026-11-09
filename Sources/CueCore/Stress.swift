import Foundation

public struct TimingStats: Equatable, Sendable {
    public var count: Int
    public var min: Double
    public var average: Double
    public var max: Double

    public init?(_ values: [Double]) {
        guard let low = values.min(), let high = values.max() else { return nil }
        count = values.count
        min = low
        average = values.reduce(0, +) / Double(values.count)
        max = high
    }
}

// The newest switch timings, oldest first.
public struct RecentTimings: Equatable, Sendable {
    public let capacity: Int
    public private(set) var values: [Double] = []

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public var stats: TimingStats? {
        TimingStats(values)
    }

    public mutating func record(_ ms: Double) {
        values.append(ms)
        if values.count > capacity { values.removeFirst(values.count - capacity) }
    }
}

// Random GO and cover presses plus arm moves, as a nervous operator would make them, sent like real keys.
public struct StressRun: Equatable, Sendable {
    public typealias Step = (command: Command, delay: TimeInterval)

    public static let defaultTotal = 1000
    public static let maxTotal = 100_000
    public static let commands: [Command] = [
        .go, .toggleCover(.black), .toggleCover(.logo(1)), .toggleCover(.logo(2)), .armPrevious, .armNext,
    ]
    public static let interval: ClosedRange<TimeInterval> = 0.3...2.0

    public let total: Int
    public private(set) var done = 0
    public private(set) var stopped = false
    // Every switch the run caused, in ms from command to commit.
    public private(set) var timings: [Double] = []

    // Never in concert: the projector would switch by itself in front of an audience.
    public init?(total: Int, mode: Mode) {
        guard mode == .rehearsal, total > 0 else { return nil }
        self.total = min(total, Self.maxTotal)
    }

    public var running: Bool {
        done < total && !stopped
    }

    public var stats: TimingStats? {
        TimingStats(timings)
    }

    // The next command and the wait before it.
    public static func step<Generator: RandomNumberGenerator>(using generator: inout Generator) -> Step {
        let command = commands[Int.random(in: commands.indices, using: &generator)]
        return (command, TimeInterval.random(in: interval, using: &generator))
    }

    // After the step's command was sent, so its switch is still recorded.
    public mutating func count() {
        if running { done += 1 }
    }

    public mutating func record(_ ms: Double) {
        if running { timings.append(ms) }
    }

    public mutating func stop() {
        stopped = true
    }
}
