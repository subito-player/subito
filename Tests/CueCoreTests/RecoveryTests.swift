import Foundation
import Testing

@testable import CueCore

private let gala = "/shows/gala.concert.json"
private let saved = Date(timeIntervalSince1970: 1_794_000_000)

private func state(
    _ path: String? = gala, clean: Bool, live: Int? = 3, at position: Double? = 134, mode: Mode = .concert,
    recoveries: Int = 0
) -> RecoveryState {
    RecoveryState(
        showPath: path, mode: mode, liveIndex: live, livePosition: position, cover: .logo(2), cleanExit: clean,
        recoveries: recoveries, savedAt: saved)
}

@Suite struct LaunchPlanTests {
    @Test func uncleanExitRecoversTheLiveCueAtItsPosition() {
        #expect(
            Recovery.plan(from: state(clean: false), launchArgument: nil)
                == .recover(gala, .concert, armIndex: 3, at: 134))
    }

    @Test func cleanExitOpensTheLastShow() {
        #expect(Recovery.plan(from: state(clean: true), launchArgument: nil) == .open(gala))
    }

    @Test func nothingSavedOrNoShowOpenStartsEmpty() {
        #expect(Recovery.plan(from: nil, launchArgument: nil) == .empty)
        #expect(Recovery.plan(from: state(nil, clean: false), launchArgument: nil) == .empty)
        #expect(Recovery.plan(from: state(nil, clean: true), launchArgument: nil) == .empty)
    }

    @Test func uncleanExitWithNothingLiveRestoresShowAndModeOnly() {
        let plan = Recovery.plan(from: state(clean: false, live: nil, at: nil, mode: .rehearsal), launchArgument: nil)
        #expect(plan == .recover(gala, .rehearsal, armIndex: nil, at: 0))
        #expect(
            Recovery.plan(from: state(clean: false, live: 0, at: nil), launchArgument: nil)
                == .recover(gala, .concert, armIndex: 0, at: 0))
    }

    @Test func launchArgumentRecoversOnlyTheSameShowAfterAnUncleanExit() {
        #expect(
            Recovery.plan(from: state(clean: false), launchArgument: gala)
                == .recover(gala, .concert, armIndex: 3, at: 134))
        #expect(Recovery.plan(from: state(clean: true), launchArgument: gala) == .open(gala))
        #expect(
            Recovery.plan(from: state(clean: false), launchArgument: "/other.movie.json") == .open("/other.movie.json"))
        #expect(Recovery.plan(from: nil, launchArgument: gala) == .open(gala))
    }

    @Test func secondCrashInARecoveredLaunchSkipsTheNextRecovery() {
        #expect(
            Recovery.plan(from: state(clean: false, recoveries: 1), launchArgument: nil)
                == .recover(gala, .concert, armIndex: 3, at: 134))
        #expect(
            Recovery.plan(from: state(clean: false, recoveries: 2), launchArgument: nil)
                == .skipRecovery(gala, .concert))
        #expect(
            Recovery.plan(from: state(clean: false, recoveries: 2), launchArgument: gala)
                == .skipRecovery(gala, .concert))
        #expect(Recovery.plan(from: state(clean: true, recoveries: 2), launchArgument: nil) == .open(gala))
    }

    @Test func recoveredLaunchesCountUpAndAnythingElseStartsOver() {
        let crashed = state(clean: false, recoveries: 1)
        #expect(Recovery.recoveries(for: .recover(gala, .concert, armIndex: 3, at: 134), from: crashed) == 2)
        #expect(Recovery.recoveries(for: .recover(gala, .concert, armIndex: nil, at: 0), from: nil) == 1)
        #expect(Recovery.recoveries(for: .skipRecovery(gala, .concert), from: state(clean: false, recoveries: 2)) == 2)
        #expect(Recovery.recoveries(for: .open(gala), from: crashed) == 0)
        #expect(Recovery.recoveries(for: .empty, from: crashed) == 0)
    }
}

@Suite struct StateFileTests {
    @Test func stateSurvivesARoundTripThroughTheFile() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("app/state.json")
            try Recovery.save(state(clean: false, recoveries: 1), to: url)
            #expect(Recovery.load(from: url) == state(clean: false, recoveries: 1))
            try Recovery.save(state(clean: true, live: nil, at: nil, mode: .rehearsal), to: url)
            #expect(Recovery.load(from: url) == state(clean: true, live: nil, at: nil, mode: .rehearsal))
            #expect(try String(contentsOf: url, encoding: .utf8).hasSuffix("}\n"))
        }
    }

    @Test func missingOrBrokenFileMeansNothingToRecover() throws {
        try withTempDir { dir in
            let url = dir.appendingPathComponent("state.json")
            #expect(Recovery.load(from: url) == nil)
            try write("{ \"showPath\": ", to: url)
            #expect(Recovery.load(from: url) == nil)
        }
    }
}
