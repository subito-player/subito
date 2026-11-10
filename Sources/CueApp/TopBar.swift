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
            ProjectorStatus(model: model).frame(maxWidth: 280, alignment: .leading).layoutPriority(1)
            AudioBadge(model: model).frame(maxWidth: 300, alignment: .leading).layoutPriority(1)
            Spacer(minLength: 8)
            if let update = model.availableUpdate { UpdateBadge(model: model, version: update.version) }
            LastKeyView(model: model).layoutPriority(1)
            LanguageSwitch(model: model).fixedSize()
            KeysButton(model: model)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Palette.panel)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }
}

struct BarButton: View {
    let text: String
    // A pending press-twice confirmation.
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(on ? AnyShapeStyle(Color.white) : AnyShapeStyle(.foreground))
                .background(on ? Palette.confirm : Palette.raise, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Palette.confirm : Palette.line))
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
        let presentation = model.effectivePresentation
        let fullscreen = presentation == .fullscreen
        let (status, text, ink): (Color, String, Color) =
            switch model.output {
            case .attached(let name, let hz, let mirrored)?:
                mirrored
                    ? (Palette.live, s.mirroring, Palette.live)
                    : (Palette.ok, s.projector(display(name), hz: hz), Palette.dim)
            case .missing?: (Palette.live, s.noProjector, Palette.live)
            case nil: (Palette.dim, "", Palette.dim)
            }
        // Red still wins; otherwise a rehearsal debug view is never shown as a green projector.
        let dot = status == Palette.ok && !fullscreen ? Palette.warn : status
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 10, height: 10)
            if !fullscreen {
                Text(s.presentation(presentation)).bold().foregroundStyle(Palette.warn).fixedSize()
            }
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

private struct UpdateBadge: View {
    let model: AppModel
    let version: AppVersion

    var body: some View {
        Button(action: model.openUpdate) {
            Text(model.strings.updateBadge(version))
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(Color.white)
                .background(Palette.confirm, in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .fixedSize()
        .layoutPriority(1)
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

private struct KeysButton: View {
    let model: AppModel

    var body: some View {
        let on = model.keysOpen
        Button(action: model.toggleKeys) {
            Text("?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(on ? Color.white : Palette.fg)
                .frame(width: 32, height: 32)
                .background(on ? Palette.confirm : Palette.raise, in: Circle())
                .overlay(Circle().strokeBorder(on ? Palette.confirm : Palette.line))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .accessibilityLabel(model.strings.keys)
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
