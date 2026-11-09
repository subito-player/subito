import CueCore
import SwiftUI

// Reads liveTime, so only this view redraws on the 10 Hz clock.
struct LiveProgress: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let clip = model.liveClip
        let time = model.liveTime
        let position = time?.position ?? 0
        let duration = max(time?.duration ?? 0, 0.001)
        let planned = clip?.plannedEndS
        let tailEnd = planned.flatMap { planned in clip?.tailS.map { planned + $0 } } ?? duration - 1
        let toEnd = clockText(duration - position, rounding: .up)
        VStack(spacing: 12) {
            ProgressTrack(
                fraction: position / duration,
                markers: [
                    planned.map { Marker(at: $0 / duration, colour: .white) },
                    Marker(at: tailEnd / duration, colour: Palette.armed),
                ].compactMap { $0 })
            HStack(alignment: .firstTextBaseline) {
                Text("\(clockText(position)) / \(clockText(duration, rounding: .toNearestOrAwayFromZero))")
                    .font(.system(size: 18).monospacedDigit())
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(planned == nil ? s.toClipEnd : s.toPlannedEnd).foregroundStyle(Palette.dim)
                    Text(planned.map { untilPlanned($0, position) } ?? toEnd)
                        .font(.system(size: 32, weight: .semibold).monospacedDigit())
                }
                Spacer()
                Text(planned == nil ? "" : "\(s.toClipEnd) \(toEnd)")
                    .font(.system(size: 16).monospacedDigit())
                    .foregroundStyle(Palette.dim)
            }
        }
        .opacity(clip != nil && time != nil ? 1 : 0)
    }

    private func untilPlanned(_ planned: Double, _ position: Double) -> String {
        position <= planned ? clockText(planned - position, rounding: .up) : "+" + clockText(position - planned)
    }
}

private struct Marker {
    let at: Double
    let colour: Color
}

private struct ProgressTrack: View {
    let fraction: Double
    let markers: [Marker]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            RoundedRectangle(cornerRadius: 4)
                .fill(Palette.raise)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(Palette.live).frame(width: width * unit(fraction))
                }
                .overlay(alignment: .leading) {
                    ForEach(markers.indices, id: \.self) { index in
                        Rectangle()
                            .fill(markers[index].colour)
                            .frame(width: 3, height: 30)
                            .offset(x: width * unit(markers[index].at) - 1.5)
                    }
                }
        }
        .frame(height: 18)
    }

    private func unit(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }
}

struct ButtonRow: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let cover = model.state.cover
        HStack(spacing: 8) {
            KeyButton(label: s.go, key: "Enter", style: .go) { model.send(.go) }
            KeyButton(label: s.play, key: "Space") { model.send(.playPause) }
            KeyButton(label: s.restart, key: "Home") { model.send(.restartLive) }
            KeyButton(label: "−30", key: "⇧←") { model.send(.seekLive(by: -30)) }
            KeyButton(label: "−5", key: "←") { model.send(.seekLive(by: -5)) }
            KeyButton(label: "+5", key: "→") { model.send(.seekLive(by: 5)) }
            KeyButton(label: "+30", key: "⇧→") { model.send(.seekLive(by: 30)) }
            KeyButton(label: s.black.uppercased(), key: "B", style: .black, on: cover == .black) {
                model.send(.toggleCover(.black))
            }
            KeyButton(label: "\(s.logo.uppercased()) 1", key: "L", on: cover == .logo(1)) {
                model.send(.toggleCover(.logo(1)))
            }
            KeyButton(label: "\(s.logo.uppercased()) 2", key: "⇧L", on: cover == .logo(2)) {
                model.send(.toggleCover(.logo(2)))
            }
            KeyButton(label: s.sound, key: "M") { model.send(.toggleMute) }
        }
    }
}

private struct KeyButton: View {
    enum Style {
        case plain, go, black
    }

    let label: String
    let key: String
    var style = Style.plain
    var on = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Text(label)
                    .font(.system(size: style == .go ? 28 : 17, weight: style == .go ? .heavy : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(key)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(style == .go ? Palette.goKey : Palette.dim)
            }
            .foregroundStyle(style == .plain ? Palette.fg : .white)
            .padding(.vertical, 10)
            .padding(.horizontal, style == .go ? 28 : 6)
            .frame(maxWidth: style == .go ? nil : .infinity, minHeight: 68)
            .background(fill, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7).strokeBorder(on ? Palette.armed : border, lineWidth: on ? 3 : 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var fill: Color {
        switch style {
        case .plain: Palette.raise
        case .go: Palette.go
        case .black: .black
        }
    }

    private var border: Color {
        switch style {
        case .plain: Palette.line
        case .go: Palette.goLine
        case .black: Palette.blackLine
        }
    }
}
