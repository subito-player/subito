import CueCore
import SwiftUI

// Non-modal: the show keys and the rest of the window keep working while it is open.
struct PreflightPanel: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(s.preflight).font(.system(size: 17, weight: .bold))
                Spacer()
                Button(action: model.togglePreflight) {
                    Text(s.close)
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Palette.raise, in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Palette.line))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
            .padding(14)
            Palette.line.frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !model.state.cues.isEmpty {
                        heading(s.showSection)
                        showRows(s)
                    }
                    heading(s.systemSection)
                    ForEach(model.systemFindings.indices, id: \.self) { index in
                        row(model.systemFindings[index], s)
                    }
                    heading(s.byHand)
                    ForEach(ManualCheck.allCases, id: \.self) { check in
                        Toggle(isOn: tick(check)) { Text(s.manual(check)).font(.system(size: 15)) }
                            .toggleStyle(.checkbox)
                            .focusable(false)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 640)
        .frame(maxHeight: 560)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
        .shadow(color: .black.opacity(0.5), radius: 12)
    }

    @ViewBuilder
    private func showRows(_ s: Strings) -> some View {
        let clips = model.state.cues.filter { if case .clip = $0.kind { true } else { false } }.count
        if model.checking {
            FindingRow(dot: Palette.dim, heading: nil, title: s.checking, detail: "")
        } else if clips > 0, !model.showFindings.contains(where: { $0.cueIndex != nil }) {
            FindingRow(dot: Palette.ok, heading: nil, title: s.everyClipPlays(clips), detail: "")
        }
        ForEach(model.showFindings.indices, id: \.self) { index in
            row(model.showFindings[index], s)
        }
    }

    private func row(_ finding: Finding, _ s: Strings) -> FindingRow {
        let cues = model.state.cues
        let cue = finding.cueIndex.flatMap { cues.indices.contains($0) ? cues[$0] : nil }
        return FindingRow(
            dot: Self.colour(finding.severity), heading: cue.map(s.title), title: s.finding(finding),
            detail: finding.detail)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.dim)
            .padding(.top, 4)
    }

    private func tick(_ check: ManualCheck) -> Binding<Bool> {
        Binding(
            get: { model.manualChecks.contains(check) },
            set: { on in
                if on { model.manualChecks.insert(check) } else { model.manualChecks.remove(check) }
            })
    }

    private static func colour(_ severity: Severity) -> Color {
        switch severity {
        case .ok: Palette.ok
        case .warn: Palette.warn
        case .block: Palette.live
        }
    }
}

private struct FindingRow: View {
    let dot: Color
    let heading: String?
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(dot).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                if let heading { Text(heading).font(.system(size: 15, weight: .bold)).lineLimit(1) }
                Text(title).font(.system(size: 15))
                if !detail.isEmpty {
                    Text(detail).font(.system(size: 13).monospacedDigit()).foregroundStyle(Palette.dim).lineLimit(1)
                }
            }
        }
    }
}
