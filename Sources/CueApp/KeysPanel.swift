import CueCore
import SwiftUI

// Non-modal and never focusable, so Enter, Space and the arrows keep reaching the key monitor.
struct KeysPanel: View {
    let model: AppModel

    var body: some View {
        let s = model.strings
        VStack(alignment: .leading, spacing: 0) {
            Text(s.keys).font(.system(size: 17, weight: .bold)).padding(14)
            Palette.line.frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(CheatSheet.sections(keyMap: model.keyMap, lang: model.lang), id: \.title) { section in
                        heading(section.title)
                        ForEach(section.rows, id: \.label) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(row.keys.joined(separator: "  "))
                                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Palette.raise, in: RoundedRectangle(cornerRadius: 4))
                                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Palette.line))
                                    .frame(width: 200, alignment: .leading)
                                Text(row.label).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(width: 680)
        // Ends above the button area at 1440x900, so GO stays visible; the list scrolls.
        .frame(maxHeight: 420)
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
        .shadow(color: .black.opacity(0.5), radius: 12)
    }

    private func heading(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 13, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Palette.dim)
            .padding(.top, 4)
    }
}
