import CueCore
import Darwin
import Foundation
import Observation

// One conversion at a time, queued; the show changes only once the new file plays.
@MainActor
@Observable
final class Converter {
    enum Phase: Equatable {
        case waiting
        case preparing
        case running(Conversion.Step, fraction: Double?)
    }

    static let pidFile = AppInfo.supportDirectory.appendingPathComponent("converter.pid")

    private(set) var tool: Conversion.Tool?
    // A nix tool's store paths, found once per session.
    private(set) var resolved: Conversion.Binaries?
    private(set) var current: URL?
    private(set) var phase = Phase.preparing
    private(set) var queue: [URL] = []
    private(set) var failures: [URL: Conversion.Failure] = [:]

    @ObservationIgnored var onConverted: (_ source: URL, _ output: URL) -> Void = { _, _ in }
    @ObservationIgnored var onFailed: (_ source: URL, Conversion.Failure) -> Void = { _, _ in }
    @ObservationIgnored private var process: ToolProcess?
    @ObservationIgnored private var cancelled = false
    @ObservationIgnored private var duration: Double?
    // Serial, so a sweep queued at open is done before the next job writes its temp file.
    @ObservationIgnored private let files = DispatchQueue(label: "converter files", qos: .utility)

    private enum Result {
        case converted(URL, Conversion.Step)
        case failed(Conversion.Failure, detail: String)
        case cancelled(detail: String)
    }

    init() {
        Self.stopLeftover()
        locate()
    }

    var pending: Int {
        queue.count + (current == nil ? 0 : 1)
    }

    // Until nix has resolved ffmpeg this session, "preparing" may mean a download.
    var downloads: Bool {
        if case .nix = tool { resolved == nil } else { false }
    }

    func phase(of url: URL) -> Phase? {
        if url == current { return phase }
        return queue.contains(url) ? .waiting : nil
    }

    // Again on every preflight open, so an ffmpeg installed while the app runs is found.
    func locate() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let found = Conversion.locate(
            ffmpeg: Conversion.ffmpegPaths(home: home, user: NSUserName()),
            nix: Conversion.nixPaths(home: home, user: NSUserName()),
            exists: FileManager.default.isExecutableFile(atPath:))
        guard found != tool else { return }
        tool = found
        resolved = nil
        Log.info("converter: \(found.map(Self.describe) ?? "no ffmpeg or nix found")")
    }

    func enqueue(_ urls: [URL]) {
        guard tool != nil else { return }
        for url in urls where url != current && !queue.contains(url) {
            queue.append(url)
            failures[url] = nil
        }
        startNext()
    }

    func cancel(_ url: URL) {
        guard url == current else {
            queue.removeAll { $0 == url }
            return
        }
        cancelled = true
        process?.stop()
    }

    func cancelAll(reason: String) {
        guard pending > 0 else { return }
        Log.info("convert: cancel all (\(reason))")
        queue.removeAll()
        if let current { cancel(current) }
    }

    // Exactly the hidden temp names of these clips, left by a crash or a force quit.
    func sweep(_ sources: [URL]) {
        let temps = Set(sources.map(Conversion.tempURL))
        files.async {
            for temp in temps where FileManager.default.fileExists(atPath: temp.path) {
                try? FileManager.default.removeItem(at: temp)
                Log.info("convert: removed leftover \(temp.path)")
            }
        }
    }

    // Quit: the child must not outlive the app, nor its half-written file.
    func shutDown() {
        queue.removeAll()
        guard let current else { return }
        cancelled = true
        process?.stop()
        let temp = Conversion.tempURL(for: current)
        files.sync {
            try? FileManager.default.removeItem(at: temp)
            try? FileManager.default.removeItem(at: Self.pidFile)
        }
        Log.info("convert: stopped by quit: \(current.path)")
    }

    private func startNext() {
        guard current == nil, let tool, !queue.isEmpty else { return }
        let source = queue.removeFirst()
        current = source
        phase = .preparing
        cancelled = false
        duration = nil
        Task {
            let result = await convert(source, with: tool)
            finish(source, result)
        }
    }

    private func convert(_ source: URL, with tool: Conversion.Tool) async -> Result {
        let folder = source.deletingLastPathComponent()
        let temp = Conversion.tempURL(for: source)
        let started = ProcessInfo.processInfo.systemUptime
        Log.info("convert start \(source.path) with \(Self.describe(tool))")
        guard FileManager.default.isWritableFile(atPath: folder.path) else {
            return .failed(.cannotSave, detail: "folder not writable: \(folder.path)")
        }
        // Ours by name: left over from a crash or a force quit.
        await remove(temp)
        guard let binaries = await binaries(for: tool) else {
            return cancelled ? .cancelled(detail: "") : .failed(.ffmpegMissing, detail: "nix could not provide ffmpeg")
        }
        var info: Conversion.SourceInfo?
        if let ffprobe = binaries.ffprobe {
            let run = await self.run(
                Conversion.Invocation(executable: ffprobe, arguments: Conversion.probeArguments(source)))
            if cancelled { return .cancelled(detail: "") }
            info = run.status == 0 ? Conversion.sourceInfo(json: run.output) : nil
            let failed = "failed (\(run.status.map(String.init) ?? "not started")) \(run.errors)"
            Log.info("convert probe: \(info.map(Self.describe) ?? failed)")
        }
        duration = info?.duration
        var step = Conversion.firstStep(videoCodec: info?.videoCodec)
        while true {
            if step == .transcode {
                let free = Self.freeBytes(folder)
                guard Conversion.enoughSpace(free: free, duration: info?.duration) else {
                    let needed = Conversion.transcodeBytes(duration: info?.duration)
                    return .failed(.diskFull, detail: "\(free ?? 0) bytes free, \(needed) needed")
                }
            }
            let stepStarted = ProcessInfo.processInfo.systemUptime
            phase = .running(step, fraction: nil)
            let arguments = Conversion.arguments(step, input: source, output: temp, hevc: info?.videoCodec == "hevc")
            let running = step
            let run = await self.run(Conversion.Invocation(executable: binaries.ffmpeg, arguments: arguments)) {
                [weak self] line in
                guard let seconds = Conversion.progressSeconds(line) else { return }
                DispatchQueue.main.async { MainActor.assumeIsolated { self?.progressed(source, running, seconds) } }
            }
            var probe = ClipProbe()
            if run.status == 0, !cancelled { probe = await PreflightRunner.probe(temp) }
            if cancelled {
                await remove(temp)
                return .cancelled(detail: run.signalled ? ", ffmpeg killed by signal \(run.status ?? 0)" : "")
            }
            let outcome = Conversion.outcome(
                of: step, exitStatus: run.status, result: probe, sourceHasAudio: info?.hasAudio ?? false)
            Log.info(
                "convert \(step): exit \(run.status.map(String.init) ?? "not started"), playable \(probe.playable), "
                    + "video \(probe.hasVideo) \(probe.codec), audio \(probe.hasAudio), "
                    + Self.seconds(since: stepStarted) + (run.errors.isEmpty ? "" : ", ffmpeg: \(run.errors)"))
            switch outcome {
            case .accept:
                let output = Conversion.outputURL(for: source) { FileManager.default.fileExists(atPath: $0.path) }
                do {
                    try FileManager.default.moveItem(at: temp, to: output)
                } catch {
                    await remove(temp)
                    return .failed(.cannotSave, detail: error.localizedDescription)
                }
                let took = Self.seconds(since: started)
                Log.info("convert done \(source.path) -> \(output.lastPathComponent) by \(step), \(took)")
                return .converted(output, step)
            case .transcode:
                await remove(temp)
                step = .transcode
            case .fail(let failure):
                await remove(temp)
                return .failed(failure, detail: run.errors)
            }
        }
    }

    // Offline first, so a cached ffmpeg never waits on the network.
    private func binaries(for tool: Conversion.Tool) async -> Conversion.Binaries? {
        switch tool {
        case .installed(let binaries):
            return binaries
        case .nix(let nix):
            if let resolved { return resolved }
            for offline in [true, false] {
                let run = await self.run(Conversion.resolveInvocation(nix: nix, offline: offline))
                if cancelled { return nil }
                let output = String(decoding: run.output, as: UTF8.self)
                let found = run.status == 0 ? Conversion.binaries(fromResolveOutput: output) : nil
                let mode = offline ? "offline" : "online"
                Log.info("converter: nix \(mode): \(found?.ffmpeg ?? "failed (\(run.status ?? -1)) \(run.errors)")")
                if let found {
                    resolved = found
                    return found
                }
            }
            return nil
        }
    }

    private func run(_ invocation: Conversion.Invocation, onLine: (@Sendable (String) -> Void)? = nil) async
        -> ToolProcess.Finished
    {
        let process = ToolProcess(pidFile: Self.pidFile)
        self.process = process
        defer { self.process = nil }
        guard !cancelled else { return ToolProcess.Finished(status: nil, signalled: false, output: Data(), errors: "") }
        return await process.run(invocation, onLine: onLine)
    }

    private func remove(_ url: URL) async {
        await withCheckedContinuation { continuation in
            files.async {
                try? FileManager.default.removeItem(at: url)
                continuation.resume()
            }
        }
    }

    private func progressed(_ source: URL, _ step: Conversion.Step, _ seconds: Double) {
        guard current == source, !cancelled else { return }
        let new = Phase.running(step, fraction: Conversion.fraction(seconds, of: duration))
        if phase != new { phase = new }
    }

    private func finish(_ source: URL, _ result: Result) {
        current = nil
        phase = .preparing
        switch result {
        case .converted(let output, _):
            onConverted(source, output)
        case .failed(let failure, let detail):
            failures[source] = failure
            Log.info("convert failed \(source.path): \(failure)\(detail.isEmpty ? "" : ": \(detail)")")
            onFailed(source, failure)
        case .cancelled(let detail):
            Log.info("convert cancelled \(source.path)\(detail)")
        }
        startNext()
    }

    // A child left by a crash or a force quit still writes its hidden temp file.
    private static func stopLeftover() {
        let file = pidFile
        guard let text = try? String(contentsOf: file, encoding: .utf8),
            let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0
        else { return }
        let written = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        try? FileManager.default.removeItem(at: file)
        var buffer = [CChar](repeating: 0, count: 256)
        let name =
            proc_name(pid, &buffer, UInt32(buffer.count)) > 0
            ? String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        let started =
            proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size
            ? Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
            : nil
        guard Conversion.isOrphan(name: name, startedAt: started, pidWrittenAt: written) else {
            Log.info("converter: pid \(pid) from the last run is not a leftover child (\(name ?? "not running"))")
            return
        }
        kill(pid, SIGKILL)
        Log.info("converter: killed leftover \(name ?? "?") pid \(pid) from a crash or force quit")
    }

    // Purgeable space counts; some volumes report it as 0, so plain free space backs it up.
    private static func freeBytes(_ folder: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        guard let values = try? folder.resourceValues(forKeys: keys) else { return nil }
        if let important = values.volumeAvailableCapacityForImportantUsage, important > 0 { return important }
        return values.volumeAvailableCapacity.map(Int64.init)
    }

    private static func describe(_ tool: Conversion.Tool) -> String {
        switch tool {
        case .installed(let binaries): binaries.ffmpeg + (binaries.ffprobe == nil ? " (no ffprobe)" : "")
        case .nix(let nix): "\(nix) shell nixpkgs#ffmpeg"
        }
    }

    private static func describe(_ info: Conversion.SourceInfo) -> String {
        let duration = info.duration.map { "\($0) s" } ?? "unknown"
        return "video \(info.videoCodec ?? "none"), audio \(info.hasAudio), duration \(duration)"
    }

    private static func seconds(since start: TimeInterval) -> String {
        String(format: "%.1f s", ProcessInfo.processInfo.systemUptime - start)
    }
}

// Unchecked Sendable: each pipe handler runs serially, and the buffers are read only after both pipes close.
final class ToolProcess: @unchecked Sendable {
    struct Finished {
        // nil: it never started.
        var status: Int32?
        // status is then the signal number.
        var signalled: Bool
        // Only when no line handler takes it.
        var output: Data
        var errors: String
    }

    private static let errorBytes = 2048
    private let process = Process()
    private let lock = NSLock()
    // Holds the running child's pid, so the next launch can stop it after a crash.
    private let pidFile: URL?
    private var stopped = false
    private var output = Data()
    private var errors = Data()

    init(pidFile: URL?) {
        self.pidFile = pidFile
    }

    func run(_ invocation: Conversion.Invocation, onLine: (@Sendable (String) -> Void)?) async -> Finished {
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        // Below playback and the control window, so a GO stays instant while ffmpeg works.
        process.qualityOfService = .background
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        let done = DispatchGroup()
        done.enter()
        stdout.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                done.leave()
                return
            }
            output.append(data)
            guard let onLine else { return }
            while let end = output.firstIndex(of: 0x0A) {
                onLine(String(decoding: output[output.startIndex..<end], as: UTF8.self))
                output.removeSubrange(output.startIndex...end)
            }
        }
        done.enter()
        stderr.fileHandleForReading.readabilityHandler = { [self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                done.leave()
                return
            }
            errors = (errors + data).suffix(Self.errorBytes)
        }
        done.enter()
        process.terminationHandler = { _ in done.leave() }
        let failure: String? = lock.withLock {
            guard !stopped else { return "cancelled before start" }
            do {
                try process.run()
                return nil
            } catch {
                return error.localizedDescription
            }
        }
        if let failure {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return Finished(status: nil, signalled: false, output: Data(), errors: failure)
        }
        if let pidFile {
            try? FileManager.default.createDirectory(
                at: pidFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data("\(process.processIdentifier)\n".utf8).write(to: pidFile, options: .atomic)
        }
        await withCheckedContinuation { continuation in
            done.notify(queue: .global(qos: .utility)) { continuation.resume() }
        }
        if let pidFile { try? FileManager.default.removeItem(at: pidFile) }
        let text = String(decoding: errors, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return Finished(
            status: process.terminationStatus, signalled: process.terminationReason == .uncaughtSignal,
            output: onLine == nil ? output : Data(), errors: text.replacingOccurrences(of: "\n", with: " | "))
    }

    // SIGKILL, so ffmpeg never finishes or rewrites a big file on its way out.
    func stop() {
        lock.withLock {
            stopped = true
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }
}
