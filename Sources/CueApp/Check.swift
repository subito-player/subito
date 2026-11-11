import CueCore
import Foundation

// Headless `--check`: preflight of the show and this Mac's default set, no windows or displays, no files written.
enum Check {
    static func run(path: String) async -> Int32 {
        Log.headless = true
        // A reader that closes early must not kill the run; the writes below ignore the error.
        signal(SIGPIPE, SIG_IGN)
        let report = await report(for: path)
        Log.flush()
        if let data = try? report.json() { try? FileHandle.standardOutput.write(contentsOf: data) }
        return report.exitCode
    }

    static func report(for path: String) async -> CheckReport {
        let url = URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
        let document: ShowDocument
        do {
            document = try ShowDocument.loadReadOnly(url)
        } catch {
            return CheckReport(
                show: path,
                error: (error as? ShowError)?.description ?? "\(url.lastPathComponent): \(error.localizedDescription)")
        }
        let cues = document.cues
        // The app's own default set, read only; a broken one counts as empty, as in the app.
        let (defaults, defaultsError) = SlotSet.load(
            from: AppInfo.supportDirectory.appendingPathComponent(SlotSet.fileName))
        let pictures = Pictures.merge(defaults: defaults, concert: document.concert, concertURL: document.url)
        let logos = pictures.map { $0?.file }
        // Loop logos and slots are probed like clips.
        let files = Set(
            cues.compactMap { cue -> URL? in if case .clip(_, let url) = cue.kind { url } else { nil } }
                + logos.compactMap { logo -> URL? in if case .loop(let url)? = logo { url } else { nil } })
        var probes: [URL: ClipProbe] = [:]
        await withTaskGroup(of: (URL, ClipProbe).self) { group in
            for file in files {
                group.addTask { (file, await PreflightRunner.probe(file)) }
            }
            for await (file, probe) in group { probes[file] = probe }
        }
        let images = Set(
            logos.compactMap { logo -> URL? in
                guard case .image(let url)? = logo, PreflightRunner.logoImage(at: url) != nil else { return nil }
                return url
            })
        let broken = defaultsError.map { [Finding(severity: .warn, kind: .defaultSet, detail: $0.description)] } ?? []
        let findings =
            broken + Preflight.evaluate(cues: cues, probes: probes, logos: logos)
            + Preflight.evaluate(pictures: pictures, images: images, probes: probes)
        return CheckReport(show: path, title: document.title, cues: cues, findings: findings)
    }
}
