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
        .opacity(model.liveSlot != nil && time != nil ? 1 : 0)
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

// GO left of two rows: the transport keys, then Logo 1, Logo 2 and slots 1 to 6.
struct ButtonRow: View {
    private static let goWidth: CGFloat = 200

    let model: AppModel

    var body: some View {
        let s = model.strings
        let cover = model.state.cover
        let key = { (command: Command) in Self.key(model.keyMap.chords(for: .command(command)).first, s) }
        HStack(spacing: 8) {
            KeyButton(label: s.go, key: key(.go), style: .go) { model.send(.go) }
                .frame(width: Self.goWidth)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    KeyButton(label: s.play, key: key(.playPause)) { model.send(.playPause) }
                    KeyButton(label: s.restart, key: key(.restartLive)) { model.send(.restartLive) }
                    KeyButton(label: "−30", key: key(.seekLive(by: -30))) { model.send(.seekLive(by: -30)) }
                    KeyButton(label: "−5", key: key(.seekLive(by: -5))) { model.send(.seekLive(by: -5)) }
                    KeyButton(label: "+5", key: key(.seekLive(by: 5))) { model.send(.seekLive(by: 5)) }
                    KeyButton(label: "+30", key: key(.seekLive(by: 30))) { model.send(.seekLive(by: 30)) }
                    KeyButton(
                        label: s.black.uppercased(), key: key(.toggleCover(.black)), style: .black,
                        on: cover == .black
                    ) {
                        model.send(.toggleCover(.black))
                    }
                    KeyButton(label: s.sound, key: key(.toggleMute)) { model.send(.toggleMute) }
                }
                Text(s.logosAndSlots.uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(Palette.dim)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    ForEach(1...pictureCount, id: \.self) { number in
                        PictureButton(model: model, number: number, key: key(.toggleCover(.logo(number))))
                    }
                }
            }
        }
        // The rows' own height, so GO stretches over both and the previews take what is left.
        .fixedSize(horizontal: false, vertical: true)
    }

    // Symbols keep the buttons narrow: ⇧← rather than Shift+←; an unbound action shows a dash.
    private static func key(_ chord: KeyChord?, _ s: Strings) -> String {
        guard let chord else { return "-" }
        let symbols: [(Modifier, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { chord.modifiers.contains($0.0) }.map(\.1).joined() + s.key(KeyChord(key: chord.key))
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
                    .font(.system(size: style == .go ? 44 : 17, weight: style == .go ? .heavy : .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(key)
                    .font(.system(size: 13, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(style == .go ? Palette.goKey : Palette.dim)
            }
            .foregroundStyle(style == .plain ? Palette.fg : .white)
            .padding(.vertical, 10)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, minHeight: 68, maxHeight: style == .go ? .infinity : nil)
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

// Outside edit mode a click is the picture's cover key; in edit mode it selects the picture for the inspector.
private struct PictureButton: View {
    let model: AppModel
    let number: Int
    let key: String

    var body: some View {
        let picture = model.pictures[number - 1]
        let on = model.state.cover == .logo(number)
        Button {
            if model.editing {
                model.selectPicture(number)
            } else {
                model.send(.toggleCover(.logo(number)))
            }
        } label: {
            Group {
                if let picture { filled(picture) } else { empty }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .frame(height: 88)
            .background(picture == nil ? Color.clear : Palette.raise, in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(
                        on ? Palette.armed : Palette.line,
                        style: StrokeStyle(lineWidth: on ? 3 : 1, dash: picture == nil && !on ? [4, 3] : []))
            )
            .overlay {
                if model.selectedPicture == number {
                    RoundedRectangle(cornerRadius: 7).strokeBorder(Palette.confirm, lineWidth: 2).padding(on ? 3 : 0)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private func filled(_ picture: CueCore.Picture) -> some View {
        let s = model.strings
        // Set but not loadable: visible here before anyone presses it.
        let broken = !model.showablePictures.contains(number)
        return VStack(alignment: .leading, spacing: 4) {
            thumbnail(s)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .topTrailing) { SourceTag(own: picture.source == .concert, strings: s).padding(2) }
            HStack(spacing: 4) {
                if broken { Circle().fill(Palette.live).frame(width: 8, height: 8) }
                Text(s.picture(number))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(broken ? Palette.live : Palette.fg)
                    .lineLimit(1)
            }
            keyText
        }
    }

    @ViewBuilder
    private func thumbnail(_ s: Strings) -> some View {
        switch model.engine.logo(number) {
        case .image(let image)?:
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
        case .loop?:
            Text(s.loopTag).font(.system(size: 11, weight: .heavy)).tracking(0.8).foregroundStyle(Palette.fg)
        case nil:
            EmptyView()
        }
    }

    private var empty: some View {
        let s = model.strings
        return VStack(spacing: 4) {
            Text(model.editing ? s.addPicture : s.emptySlot).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            keyText
        }
        .foregroundStyle(Palette.dim)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var keyText: some View {
        Text(key)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .foregroundStyle(Palette.dim)
    }
}

// Where a picture comes from: the default set on this Mac, or the open concert.
struct SourceTag: View {
    let own: Bool
    let strings: Strings

    var body: some View {
        Text(own ? strings.concertTag : strings.defaultTag)
            .font(.system(size: 9, weight: .heavy))
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .foregroundStyle(.white)
            .background(own ? Palette.confirm : Palette.line, in: RoundedRectangle(cornerRadius: 3))
    }
}
