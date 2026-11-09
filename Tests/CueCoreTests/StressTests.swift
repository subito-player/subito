import Foundation
import Testing

@testable import CueCore

// Seeded, so a failing run can be replayed.
private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct TimingTests {
    @Test func statsGiveMinAverageAndMax() throws {
        let stats = try #require(TimingStats([4, 2, 9]))
        #expect(stats == TimingStats([2, 9, 4]))
        #expect((stats.count, stats.min, stats.average, stats.max) == (3, 2, 5, 9))
        #expect(TimingStats([]) == nil)
    }

    @Test func recentKeepsOnlyTheNewestTwenty() throws {
        var recent = RecentTimings(capacity: 20)
        #expect(recent.stats == nil)
        for ms in 1...25 { recent.record(Double(ms)) }
        #expect(recent.values == (6...25).map(Double.init))
        let stats = try #require(recent.stats)
        #expect((stats.count, stats.min, stats.max) == (20, 6, 25))
    }
}

@Suite struct StressRunTests {
    @Test func neverInConcertOrWithNothingToDo() {
        #expect(StressRun(total: 1000, mode: .concert) == nil)
        #expect(StressRun(total: 0, mode: .rehearsal) == nil)
        #expect(StressRun(total: 1_000_000, mode: .rehearsal)?.total == StressRun.maxTotal)
    }

    @Test func stepsPickTheSixKeysAtHumanIntervals() {
        var generator = SplitMix64(state: 42)
        var seen: [Command] = []
        for _ in 0..<1000 {
            let step = StressRun.step(using: &generator)
            #expect(StressRun.commands.contains(step.command))
            #expect(StressRun.interval.contains(step.delay))
            if !seen.contains(step.command) { seen.append(step.command) }
        }
        #expect(seen.count == 6)
        #expect(!StressRun.commands.contains(.toggleMute))
        #expect(!StressRun.commands.contains(.playPause))
    }

    @Test func runsExactlyItsTotalAndTimesOnlyItsOwnSwitches() throws {
        var run = try #require(StressRun(total: 3, mode: .rehearsal))
        for ms in [5.0, 7, 3] {
            #expect(run.running)
            run.record(ms)
            run.count()
        }
        #expect(!run.running)
        #expect(run.done == 3)
        run.record(100)
        run.count()
        #expect(run.done == 3)
        #expect(run.timings == [5, 7, 3])
        #expect(run.stats?.max == 7)
    }

    @Test func stopEndsTheRunWhereItIs() throws {
        var run = try #require(StressRun(total: 1000, mode: .rehearsal))
        run.record(4)
        run.count()
        run.stop()
        run.record(9)
        run.count()
        #expect(!run.running)
        #expect((run.done, run.timings) == (1, [4]))
    }
}
