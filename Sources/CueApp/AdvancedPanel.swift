import CueCore
import SwiftUI

// Owner only. Non-modal like the preflight panel: the show keys keep working while it is open.
struct AdvancedPanel: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let advanced = model.advanced
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Tag(text: s.advanced, fill: Palette.unlocked, ink: .white)
                Text("\(s.version) \(AppInfo.version ?? "dev")").foregroundStyle(Palette.dim)
                Spacer()
                BarButton(text: s.close, action: advanced.close)
            }
            .padding(14)
            Palette.line.frame(height: 1)
            VStack(alignment: .leading, spacing: 8) {
                system(s)
                heading(s.goTimings(Advanced.goTimingCount))
                Text(advanced.goTimings.stats.map(s.timings) ?? s.noGoYet)
                Text(advanced.goTimings.values.map { String(format: "%.1f", $0) }.joined(separator: "  "))
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                heading(s.stressTest)
                StressControls(model: model)
                // They hand focus to Finder or the browser, so a concert never gets them.
                let concert = model.state.mode == .concert
                HStack(spacing: 8) {
                    BarButton(text: s.cheatSheet, action: model.openCheatSheet)
                    BarButton(text: s.openKeyMap, action: model.revealKeyMap)
                    BarButton(text: s.openLogFolder, action: model.openLogFolder)
                }
                .disabled(concert)
                .opacity(concert ? 0.55 : 1)
                .padding(.top, 6)
            }
            .padding(14)
            Palette.line.frame(height: 1)
            heading(s.logTail(Advanced.logLines)).padding(.horizontal, 14).padding(.top, 10)
            LogTail(lines: advanced.logTail)
        }
        .font(.system(size: 15))
        .frame(width: 760)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.unlocked, lineWidth: 2))
        .shadow(color: .black.opacity(0.5), radius: 12)
    }

    @ViewBuilder
    private func system(_ s: Strings) -> some View {
        let advanced = model.advanced
        let rate = model.systemFindings.first { $0.kind == .refreshRate || $0.kind == .betterRefreshRate }
        row(s.output, output(s))
        if let rate { row(s.finding(Finding(severity: .ok, kind: .refreshRate)), rate.detail) }
        row(
            s.memory,
            s.memory(now: Advanced.megabytes(advanced.memory), launch: Advanced.megabytes(advanced.memoryAtLaunch)))
    }

    private func output(_ s: Strings) -> String {
        switch model.output {
        case .attached(let name, _, let mirrored)?:
            mirrored ? s.mirroring : s.display(name, id: model.outputDisplay ?? 0)
        case .missing?: s.noProjector
        case nil: "-"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(Palette.dim).lineLimit(1).frame(width: 190, alignment: .leading)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.dim)
            .padding(.top, 6)
    }
}

// Concert shows no field at all, so nothing in this panel can take the keyboard during a show.
private struct StressControls: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let advanced = model.advanced
        if model.state.mode == .concert {
            HStack(spacing: 10) {
                BarButton(text: s.start, action: advanced.startStress).disabled(true).opacity(0.55)
                Text(s.stressRehearsalOnly).foregroundStyle(Palette.warn)
            }
        } else {
            HStack(spacing: 10) {
                TextField("", text: Binding(get: { advanced.stressCount }, set: { advanced.stressCount = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 90)
                    .disabled(advanced.stressRunning)
                Text(s.switches).foregroundStyle(Palette.dim)
                if advanced.stressRunning {
                    BarButton(text: s.stop) { advanced.stopStress(reason: "Stop button") }
                } else {
                    BarButton(text: s.start, action: advanced.startStress)
                }
                if let run = advanced.stress {
                    Text("\(run.done) / \(run.total)").monospacedDigit()
                    Text(run.running ? s.stressRunning : run.done == run.total ? s.stressDone : s.stressStopped)
                        .foregroundStyle(run.running ? Palette.warn : Palette.dim)
                }
            }
        }
        if let stats = advanced.stress?.stats { Text(s.timings(stats)) }
    }
}

private struct LogTail: View {
    let lines: [String]

    // Starts at the newest line; no forced scroll, so older lines stay readable while new ones arrive.
    var body: some View {
        ScrollView {
            Text(lines.joined(separator: "\n"))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Palette.dim)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
        }
        .defaultScrollAnchor(.bottom)
    }
}
