import CueCore
import SwiftUI

// Colours from design/control-window.html; the control window is always dark.
enum Palette {
    static let bg = Color(hex: 0x101114)
    static let panel = Color(hex: 0x17181D)
    static let raise = Color(hex: 0x20222A)
    static let line = Color(hex: 0x30333D)
    static let fg = Color(hex: 0xE3E5EA)
    static let dim = Color(hex: 0x8B90A0)
    static let live = Color(hex: 0xFF3B30)
    static let liveBg = Color(hex: 0x4D1513)
    static let armed = Color(hex: 0xFFB020)
    static let armedBg = Color(hex: 0x45360C)
    static let ok = Color(hex: 0x3CCF6B)
    static let warn = Color(hex: 0xFFB020)
    static let go = Color(hex: 0x1F7A33)
    static let goLine = Color(hex: 0x34A853)
    static let goKey = Color(hex: 0xC9F0D2)
    static let confirm = Color(hex: 0x2D5FD8)
    static let blackLine = Color(hex: 0x777777)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct ControlView: View {
    let model: AppModel
    let focusControl: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TopBar(model: model)
            BannerRow(model: model, focusControl: focusControl)
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    CueList(model: model)
                        .frame(width: geometry.size.width * 0.3)
                        .background(Palette.panel)
                    Palette.line.frame(width: 1)
                    VStack(alignment: .leading, spacing: 16) {
                        Previews(model: model)
                        LiveProgress(model: model)
                        ButtonRow(model: model)
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                }
            }
            StatusLine(model: model)
        }
        .font(.system(size: 15))
        .foregroundStyle(Palette.fg)
        .background(Palette.bg)
        .environment(\.colorScheme, .dark)
    }
}

struct Tag: View {
    let text: String
    let fill: Color
    let ink: Color
    var outlined = false

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .foregroundStyle(ink)
            .background(fill, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(outlined ? Palette.line : .clear))
    }
}

// Always takes its height, so a banner appearing never shifts the list or the buttons.
private struct BannerRow: View {
    let model: AppModel
    let focusControl: () -> Void

    var body: some View {
        let s = model.strings
        ZStack {
            switch model.banner {
            case .focusLost?:
                Button(action: focusControl) { banner(s.focusLost, Palette.live) }
                    .buttonStyle(.plain)
                    .focusable(false)
            case .confirmOutput(let choice)?:
                banner(s.confirmOutput(model.name(of: choice, s)), Palette.confirm)
            case .confirm(let notice)?:
                banner(s.notice(notice), Palette.confirm)
            case .noProjector?:
                banner(s.noProjectorBanner, Palette.live)
            case nil:
                EmptyView()
            }
        }
        .frame(height: 40)
    }

    private func banner(_ text: String, _ fill: Color) -> some View {
        Text(text)
            .font(.system(size: 18, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(fill)
            .contentShape(Rectangle())
    }
}

private struct StatusLine: View {
    let model: AppModel

    var body: some View {
        HStack(spacing: 16) {
            message(model.strings).lineLimit(1)
            Spacer(minLength: 0)
            OutputChips(model: model).fixedSize()
        }
        .font(.system(size: 16, weight: .medium))
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(Palette.panel)
        .overlay(alignment: .top) { Palette.line.frame(height: 1) }
    }

    // Errors in red first, then warnings in amber; "all good" only when nothing at all is off.
    private func message(_ s: Strings) -> Text {
        if let notice = model.statusNotice { return Text(s.notice(notice)).foregroundStyle(Palette.warn) }
        let cue = { (url: URL) in model.cue(for: url).map(s.title) ?? url.lastPathComponent }
        var parts: [(String, Color)] = model.problems.map { (s.problem($0), Palette.live) }
        for error in model.loadErrors where !error.warning {
            parts.append((s.cannotPlay(cue(error.url), reason: error.message), Palette.live))
        }
        for error in model.loadErrors where error.warning {
            parts.append((s.pictureUnconfirmed(cue(error.url)), Palette.warn))
        }
        if model.output == .missing { parts.append((s.noProjectorStatus, Palette.live)) }
        let showFailed = model.problems.contains { if case .show = $0 { true } else { false } }
        if model.state.cues.isEmpty, !showFailed { parts.append((s.noShow, Palette.warn)) }
        guard !parts.isEmpty else { return Text(s.allGood).foregroundStyle(Palette.ok) }
        return parts.dropFirst().reduce(Text(parts[0].0).foregroundStyle(parts[0].1)) { line, part in
            line + Text("  ·  ").foregroundStyle(Palette.dim) + Text(part.0).foregroundStyle(part.1)
        }
    }
}

// Plain buttons, not a Menu: an open menu's tracking loop would take Enter and arrows from the key monitor.
private struct OutputChips: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        HStack(spacing: 6) {
            Text("\(s.output):").foregroundStyle(Palette.dim)
            chip(s.automatic, on: model.automaticOutput) { model.pickOutput(.automatic) }
            if model.displays.isEmpty {
                Text(s.noExternalDisplay).foregroundStyle(Palette.dim)
            }
            ForEach(model.displays) { display in
                chip(s.display(display.name, id: display.id), on: display.id == model.outputDisplay) {
                    model.pickOutput(.display(display.id))
                }
            }
        }
        .font(.system(size: 14, weight: .semibold))
    }

    private func chip(_ text: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(on ? Color.white : Palette.fg)
                .background(on ? Palette.confirm : Palette.raise, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(on ? Palette.confirm : Palette.line))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}
