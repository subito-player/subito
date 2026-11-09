import AppKit
import CueCore
import Observation

@MainActor
@Observable
final class Advanced {
    static let logLines = 200
    static let goTimingCount = 20
    static let memoryEveryTicks = 10

    private(set) var open = false
    private(set) var logTail: [String] = []
    private(set) var goTimings = RecentTimings(capacity: Advanced.goTimingCount)
    let memoryAtLaunch = ProcessMemory.resident()
    private(set) var memory: UInt64?
    private(set) var stress: StressRun?
    var stressCount = String(StressRun.defaultTotal)

    // Set by the model; the stress runner presses keys through the same path as the keyboard.
    @ObservationIgnored var send: (Command) -> Void = { _ in }
    @ObservationIgnored var mode: () -> Mode = { .concert }
    @ObservationIgnored private var refresh: Timer?
    @ObservationIgnored private var stressTimer: Timer?
    @ObservationIgnored private var ticks = 0
    @ObservationIgnored private var generator = SystemRandomNumberGenerator()

    var stressRunning: Bool {
        stress?.running ?? false
    }

    func toggle() {
        open ? close() : show()
    }

    func close() {
        guard open else { return }
        stopStress(reason: "Advanced view closed")
        open = false
        refresh?.invalidate()
        refresh = nil
        Log.info("advanced view closed")
    }

    func recordSwitch(ms: Double, go: Bool) {
        if go { goTimings.record(ms) }
        if stressRunning { stress?.record(ms) }
    }

    func startStress() {
        guard !stressRunning else { return }
        let total = max(1, Int(stressCount.trimmingCharacters(in: .whitespaces)) ?? StressRun.defaultTotal)
        guard let run = StressRun(total: total, mode: mode()) else {
            Log.info("stress test refused: mode \(mode().rawValue), \(total) switches")
            return
        }
        stress = run
        stressCount = String(run.total)
        sampleMemory()
        Log.info("stress start: \(run.total) switches, memory \(Self.megabytes(memory))")
        scheduleStress()
    }

    func stopStress(reason: String) {
        guard stressRunning else { return }
        stress?.stop()
        stressTimer?.invalidate()
        stressTimer = nil
        logStressEnd("stopped (\(reason))")
    }

    private func show() {
        open = true
        Log.info("advanced view opened")
        ticks = 0
        tick()
        refresh = Self.timer(after: 1, repeats: true) { [weak self] in self?.tick() }
    }

    private func tick() {
        logTail = TextTail.lastLines(of: Log.todayFile, count: Self.logLines)
        if ticks % Self.memoryEveryTicks == 0 { sampleMemory() }
        ticks += 1
    }

    private func sampleMemory() {
        memory = ProcessMemory.resident()
    }

    private func scheduleStress() {
        let step = StressRun.step(using: &generator)
        stressTimer = Self.timer(after: step.delay, repeats: false) { [weak self] in self?.fire(step.command) }
    }

    private func fire(_ command: Command) {
        guard let run = stress, run.running else { return }
        // The mode can change by mouse mid-run; concert never gets a random switch.
        guard mode() == .rehearsal else {
            stopStress(reason: "concert mode")
            return
        }
        Log.deferred("stress \(run.done + 1)/\(run.total) \(command)")
        send(command)
        stress?.count()
        if stressRunning {
            scheduleStress()
        } else {
            logStressEnd("done")
        }
    }

    private func logStressEnd(_ how: String) {
        guard let run = stress else { return }
        sampleMemory()
        let stats = run.stats.map { String(format: "min %.1f avg %.1f max %.1f ms", $0.min, $0.average, $0.max) }
        Log.info(
            "stress \(how): \(run.done)/\(run.total) steps, \(run.timings.count) switches \(stats ?? "-"), "
                + "memory \(Self.megabytes(memory)), at launch \(Self.megabytes(memoryAtLaunch))")
    }

    static func megabytes(_ bytes: UInt64?) -> String {
        bytes.map { "\($0 / 1_048_576) MB" } ?? "?"
    }

    // Common mode keeps the timers running while a menu or slider tracks the mouse.
    private static func timer(after seconds: TimeInterval, repeats: Bool, _ body: @escaping @MainActor () -> Void)
        -> Timer
    {
        let timer = Timer(timeInterval: seconds, repeats: repeats) { _ in MainActor.assumeIsolated(body) }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

enum ProcessMemory {
    // Resident size, as task_info reports it for this process.
    static func resident() -> UInt64? {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.resident_size : nil
    }
}
