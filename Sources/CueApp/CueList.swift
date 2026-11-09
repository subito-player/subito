import CueCore
import SwiftUI

struct CueList: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        let state = model.state
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if state.cues.isEmpty {
                        Text(s.noShow).foregroundStyle(Palette.dim).padding(16)
                    }
                    ForEach(Array(state.cues.enumerated()), id: \.offset) { index, cue in
                        if let movie = cue.movieIndex, index == 0 || state.cues[index - 1].movieIndex != movie {
                            Text(header(movie))
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                        }
                        CueRow(
                            number: s.number(cue), label: s.label(cue), meta: meta(cue),
                            role: index == state.liveIndex ? .live : index == state.armedIndex ? .armed : nil
                        ) {
                            model.send(.arm(index: index))
                        }
                        .id(index)
                    }
                }
                .padding(.vertical, 6)
            }
            .onAppear { reveal(proxy) }
            .onChange(of: state.liveIndex) { reveal(proxy) }
            .onChange(of: state.armedIndex) { reveal(proxy) }
        }
    }

    private func header(_ movie: Int) -> String {
        let title = model.movieTitles.indices.contains(movie) ? model.movieTitles[movie] : ""
        return "\(movie + 1) · \(title)".uppercased()
    }

    private func meta(_ cue: Cue) -> String {
        guard case .clip(_, let url) = cue.kind, let duration = model.durations[url] else { return "" }
        return clockText(duration, rounding: .toNearestOrAwayFromZero)
    }

    // No anchor scrolls only as far as needed, so the list never jumps when both rows are already visible.
    private func reveal(_ proxy: ScrollViewProxy) {
        if let live = model.state.liveIndex { proxy.scrollTo(live) }
        if let armed = model.state.armedIndex { proxy.scrollTo(armed) }
    }
}

private struct CueRow: View {
    enum Role {
        case live, armed
    }

    let number: String
    let label: String
    let meta: String
    let role: Role?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(number)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Palette.dim)
                    .frame(minWidth: 24, alignment: .leading)
                Text(label).font(.system(size: 17)).lineLimit(1)
                Spacer(minLength: 8)
                Text(meta).font(.system(size: 14).monospacedDigit()).foregroundStyle(Palette.dim)
            }
            .padding(.vertical, 7)
            .padding(.leading, 16)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background)
            .overlay(alignment: .leading) { bar.frame(width: 4) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var background: Color {
        switch role {
        case .live: Palette.liveBg
        case .armed: Palette.armedBg
        case nil: .clear
        }
    }

    private var bar: Color {
        switch role {
        case .live: Palette.live
        case .armed: Palette.armed
        case nil: .clear
        }
    }
}
