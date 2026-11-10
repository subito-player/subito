import CueCore
import Foundation

// Headless `--check`: preflight of the show only, no windows or displays, no files written.
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

    private static func report(for path: String) async -> CheckReport {
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
        let logos = document.logos
        // Loop logos are probed like clips.
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
        let findings =
            Preflight.evaluate(cues: cues, probes: probes, logos: logos)
            + Preflight.evaluate(logos: logos, images: images, probes: probes)
        return CheckReport(show: path, title: document.title, cues: cues, findings: findings)
    }
}
