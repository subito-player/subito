import CueCore
import SwiftUI

struct TopBar: View {
    let model: AppModel
    let pickers: Pickers

    var body: some View {
        let s = model.strings
        HStack(spacing: 16) {
            ModeSwitch(model: model).fixedSize()
            Text(model.title ?? s.noShow)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(1)
                .frame(minWidth: 140, alignment: .leading)
            // Rehearsal only: an unlocked concert may edit its show but never swap it for another.
            if model.state.mode == .rehearsal {
                HStack(spacing: 8) {
                    BarButton(text: s.open, action: pickers.openShow)
                    BarButton(text: s.newMovie, action: pickers.newMovie)
                    BarButton(text: s.newConcert, action: pickers.newConcert)
                }
                .fixedSize()
            }
            ProjectorStatus(model: model).frame(maxWidth: 280, alignment: .leading).layoutPriority(1)
            AudioBadge(model: model).frame(maxWidth: 300, alignment: .leading).layoutPriority(1)
            Spacer(minLength: 8)
            LastKeyView(model: model).layoutPriority(1)
            LanguageSwitch(model: model).fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Palette.panel)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }
}

struct BarButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(Palette.raise, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// Clicking the other mode asks for a second click within 3 s; the output never changes.
private struct ModeSwitch: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach([Mode.rehearsal, .concert], id: \.self) { mode in
                let on = model.state.mode == mode
                Button {
                    model.requestMode(mode)
                } label: {
                    Text(model.strings.name(mode))
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .foregroundStyle(on ? Color.white : Palette.dim)
                        .background(on ? (mode == .concert ? Palette.live : Palette.confirm) : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
    }
}

private struct ProjectorStatus: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let (dot, text, ink): (Color, String, Color) =
            switch model.output {
            case .attached(let name, let hz, let mirrored)?:
                mirrored
                    ? (Palette.live, s.mirroring, Palette.live)
                    : (Palette.ok, s.projector(display(name), hz: hz), Palette.dim)
            case .missing?: (Palette.live, s.noProjector, Palette.live)
            case nil: (Palette.dim, "", Palette.dim)
            }
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 10, height: 10)
            Text(text).foregroundStyle(ink).lineLimit(1)
        }
        .font(.system(size: 15, weight: dot == Palette.live ? .bold : .regular))
    }

    private func display(_ name: String?) -> String {
        model.strings.display(name, id: model.outputDisplay ?? 0)
    }
}

private struct AudioBadge: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let on = !model.state.muted
        Text(on ? s.audioOn(device: model.audioDevice) : s.muted)
            .font(.system(size: 15, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(on ? Color.black : Palette.dim)
            .background(on ? Palette.warn : Palette.raise, in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct LastKeyView: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        HStack(spacing: 6) {
            Text(s.lastKey).foregroundStyle(Palette.dim).fixedSize()
            Text(model.lastKey.map { s.key($0.chord) } ?? "-")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Palette.raise, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line))
            if let result = model.lastKey?.result {
                Text("→ \(s.action(result))").truncationMode(.tail)
            }
        }
        .font(.system(size: 15))
        .lineLimit(1)
        // Fixed, so a long key or action never pushes the rest of the bar around.
        .frame(width: 300, alignment: .leading)
    }
}

private struct LanguageSwitch: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Lang.allCases, id: \.self) { lang in
                let on = model.lang == lang
                Button {
                    model.lang = lang
                } label: {
                    Text(lang.rawValue.uppercased())
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .foregroundStyle(on ? Color.white : Palette.dim)
                        .background(on ? Palette.confirm : Color.clear)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.line))
    }
}
