import AVFoundation
import AppKit
import CueCore
import SwiftUI

struct Previews: View {
    private static let gap: CGFloat = 14

    let model: AppModel
    // Only while the park slider is dragged; released, it becomes parkArmedAt.
    @State private var scrub: Double?

    var body: some View {
        let s = model.strings
        let state = model.state
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: Self.gap) {
                liveLabel(s, state).frame(maxWidth: .infinity, alignment: .leading)
                nextLabel(s, state).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: Self.gap) {
                Screen { liveContent(state) }.frame(maxWidth: .infinity)
                Screen { nextContent(s, state) }.frame(maxWidth: .infinity)
            }
            .overlay {
                GeometryReader { geometry in
                    slotPreview(.a, state, in: geometry.size)
                    slotPreview(.b, state, in: geometry.size)
                }
            }
            HStack(spacing: Self.gap) {
                Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                scrubber(state).frame(maxWidth: .infinity)
            }
        }
    }

    // One fixed layer per slot, moved between the boxes by role, so GO never re-points a layer at another player.
    private func slotPreview(_ slot: Slot, _ state: ShowState, in size: CGSize) -> some View {
        let half = max(0, (size.width - Self.gap) / 2)
        let width = min(half, size.height * 16 / 9)
        let next = state.armedSlot == slot
        let shown = next || state.base == .clip(slot)
        return PlayerPreview(player: model.engine.player(for: slot))
            .frame(width: width, height: width * 9 / 16)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .offset(x: (half - width) / 2 + (next ? half + Self.gap : 0), y: (size.height - width * 9 / 16) / 2)
            .opacity(shown ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func liveLabel(_ s: Strings, _ state: ShowState) -> some View {
        HStack(spacing: 8) {
            Tag(text: s.live, fill: Palette.live, ink: .white)
            Text(state.liveIndex.map { s.title(state.cues[$0]) } ?? s.black).lineLimit(1)
            if state.cover != nil {
                let play = state.livePlaying ? s.running : s.paused
                Tag(
                    text: model.liveSlot == nil ? s.covered : "\(s.covered) · \(play)", fill: Palette.raise,
                    ink: Palette.fg, outlined: true)
            }
        }
        .font(.system(size: 15, weight: .bold))
    }

    private func nextLabel(_ s: Strings, _ state: ShowState) -> some View {
        var text = s.nothing
        if let index = state.armedIndex {
            text = s.title(state.cues[index])
            let at = scrub ?? state.armedAt
            if state.armedSlot != nil, at > 0 { text += " @ \(clockText(at))" }
            if state.armedSlot != nil, !state.armedReady { text += " · \(s.loading)" }
        }
        return HStack(spacing: 8) {
            Tag(text: s.next, fill: Palette.armed, ink: .black)
            Text(text).lineLimit(1)
        }
        .font(.system(size: 15, weight: .bold).monospacedDigit())
    }

    @ViewBuilder
    private func liveContent(_ state: ShowState) -> some View {
        switch state.base {
        case .black: EmptyView()
        case .logo(let number): LogoPreview(image: model.engine.logo(number))
        case .breakScreen: BreakPreview(title: model.engine.breakTitle, countdown: model.breakCountdown)
        case .clip: EmptyView()
        }
    }

    @ViewBuilder
    private func nextContent(_ s: Strings, _ state: ShowState) -> some View {
        if let index = state.armedIndex {
            switch state.cues[index].kind {
            case .clip, .black:
                EmptyView()
            case .logo(let number):
                LogoPreview(image: model.engine.logo(number))
            case .breakScreen(let item):
                let now = Date()
                BreakPreview(
                    title: item.text ?? s.breakTitle,
                    countdown: PlaybackEngine.breakCountdown(item, startedAt: now, now: now))
            }
        }
    }

    private func scrubber(_ state: ShowState) -> some View {
        let duration = model.armedTime?.duration ?? 0
        let enabled = state.armedSlot != nil && state.armedReady && duration > 0
        return Slider(
            value: Binding(get: { scrub ?? state.armedAt }, set: { scrub = $0 }),
            in: 0...max(duration, 1),
            onEditingChanged: { editing in
                guard !editing, let value = scrub else { return }
                scrub = nil
                model.send(.parkArmedAt(value))
            }
        )
        .tint(Palette.armed)
        .disabled(!enabled)
        .focusable(false)
    }
}

private struct Screen<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            Color.black
            content
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

private struct LogoPreview: View {
    let image: CGImage?

    var body: some View {
        if let image {
            Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fit)
        }
    }
}

// Same proportions as the projector's break layers in OutputWindow.
private struct BreakPreview: View {
    let title: String
    let countdown: String?

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            VStack(spacing: height * 0.05) {
                Text(title).font(.system(size: max(1, height * 0.12), weight: .semibold))
                if let countdown {
                    Text(countdown).font(.system(size: max(1, height * 0.24), weight: .semibold).monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct PlayerPreview: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        return view
    }

    func updateNSView(_ view: PlayerLayerView, context: Context) {}
}

private final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        playerLayer.videoGravity = .resizeAspect
        playerLayer.backgroundColor = CGColor.black
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func makeBackingLayer() -> CALayer {
        playerLayer
    }
}
