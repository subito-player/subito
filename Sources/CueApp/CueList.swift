import CueCore
import SwiftUI
import UniformTypeIdentifiers

struct CueList: View {
    let model: AppModel
    let pickers: Pickers

    var body: some View {
        VStack(spacing: 0) {
            if model.state.mode == .rehearsal || (model.canEdit && model.document != nil) { header }
            list
            if model.editing {
                Palette.line.frame(height: 1)
                AddBar(model: model, pickers: pickers)
                Palette.line.frame(height: 1)
                Inspector(model: model, pickers: pickers)
            }
        }
    }

    private var header: some View {
        let s = model.strings
        return HStack(spacing: 8) {
            // Rehearsal only: an unlocked concert may edit its show but never swap it for another.
            if model.state.mode == .rehearsal {
                BarButton(text: s.open, action: pickers.openShow)
                BarButton(text: s.newMovie, action: pickers.newMovie)
                BarButton(text: s.newConcert, action: pickers.newConcert)
            }
            Spacer(minLength: 0)
            if model.canEdit, model.document != nil { editToggle }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) { Palette.line.frame(height: 1) }
    }

    private var editToggle: some View {
        Button(action: model.toggleEditing) {
            Text(model.strings.edit)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .foregroundStyle(model.editing ? Color.white : Palette.fg)
                .background(model.editing ? Palette.confirm : Palette.raise, in: RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5).strokeBorder(model.editing ? Palette.confirm : Palette.line)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
    }

    private var list: some View {
        let s = model.strings
        let state = model.state
        let blocked = model.blockedCues
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if model.document == nil {
                        Text(s.noShow).foregroundStyle(Palette.dim).padding(16)
                    }
                    ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                        switch row.kind {
                        case .movie(let movie, let title):
                            Text("\(movie + 1) · \(title)".uppercased())
                                .font(.system(size: 13, weight: .semibold))
                                .tracking(0.8)
                                .foregroundStyle(Palette.dim)
                                .lineLimit(1)
                                .padding(.horizontal, 14)
                                .padding(.top, 14)
                                .padding(.bottom, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(RowControls(model: model, place: row.place) {})
                        case .cue(let index) where state.cues.indices.contains(index):
                            let cue = state.cues[index]
                            CueRow(
                                number: s.number(cue), label: s.label(cue), meta: meta(cue),
                                blocked: blocked.contains(index),
                                role: index == state.liveIndex ? .live : index == state.armedIndex ? .armed : nil
                            )
                            .modifier(RowControls(model: model, place: row.place) { model.send(.arm(index: index)) })
                            .id(index)
                        case .cue:
                            EmptyView()
                        }
                    }
                }
                .padding(.vertical, 6)
            }
            .onDrop(of: [.fileURL], delegate: ListDrop(model: model, target: nil))
            .onAppear { reveal(proxy) }
            .onChange(of: state.liveIndex) { reveal(proxy) }
            .onChange(of: state.armedIndex) { reveal(proxy) }
        }
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

// Outside edit mode a click arms; in edit mode it selects, and the row gets delete, drag and drop.
private struct RowControls: ViewModifier {
    let model: AppModel
    let place: Place?
    let tap: () -> Void

    func body(content: Content) -> some View {
        if model.editing, let place {
            let locked = model.isLocked(place)
            HStack(spacing: 0) {
                content
                trailing(place, locked: locked).frame(width: 40)
            }
            .overlay {
                if model.selection == place {
                    RoundedRectangle(cornerRadius: 3).strokeBorder(Palette.confirm, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.select(place) }
            .draggable(unless: locked) { model.startDrag(place) }
            .onDrop(of: [.fileURL, .utf8PlainText], delegate: ListDrop(model: model, target: place))
        } else {
            content.contentShape(Rectangle()).onTapGesture(perform: tap)
        }
    }

    @ViewBuilder
    private func trailing(_ place: Place, locked: Bool) -> some View {
        if locked {
            Image(systemName: "lock.fill").foregroundStyle(Palette.live)
        } else {
            let pending = model.deletePending == place
            Button {
                model.requestDelete(place)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(pending ? Color.white : Palette.dim)
                    .padding(6)
                    .background(pending ? Palette.confirm : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
        }
    }
}

extension View {
    // The live row stays put: no drag starts from it.
    @ViewBuilder
    fileprivate func draggable(unless locked: Bool, token: @escaping () -> String) -> some View {
        if locked {
            self
        } else {
            onDrag { NSItemProvider(object: token() as NSString) }
        }
    }
}

// Finder files become clips anywhere on the list; a row also takes rows of its own file.
private struct ListDrop: DropDelegate {
    let model: AppModel
    let target: Place?

    func validateDrop(info: DropInfo) -> Bool {
        model.editing
            && (info.hasItemsConforming(to: [.fileURL])
                || (target != nil && info.hasItemsConforming(to: [.utf8PlainText])))
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: info.hasItemsConforming(to: [.fileURL]) ? .copy : .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        let model = model
        let all = info.itemProviders(for: [.fileURL, .utf8PlainText])
        let kind = DropKind.classify(all.map(\.registeredTypeIdentifiers))
        Log.deferred("drop \(kind) on row \(target.map { "\($0.index)" } ?? "list")")
        if kind == .files {
            let files = all.filter { DropKind.classify([$0.registeredTypeIdentifiers]) == .files }
            Self.load(files) { urls in model.addClips(urls) }
            return true
        }
        guard kind == .row, let target, let provider = all.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, error in
            let token = object as? String
            if token == nil { Log.deferred("drop token unreadable: \(String(describing: error))") }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let token { model.drop(token: token, onto: target) }
                }
            }
        }
        return true
    }

    private static func load(_ providers: [NSItemProvider], then done: @escaping @MainActor ([URL]) -> Void) {
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let item = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                if let url = (item as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) ?? (item as? URL)
                {
                    urls.append(url)
                }
            }
            done(urls)
        }
    }
}

private struct AddBar: View {
    let model: AppModel
    let pickers: Pickers

    var body: some View {
        let s = model.strings
        HStack(spacing: 6) {
            BarButton(text: s.addClip, action: pickers.addClips)
            BarButton(text: s.addBlack) { model.add(.black) }
            BarButton(text: s.addBreak) { model.add(.breakScreen(BreakItem(minutes: 20, countdown: true))) }
            BarButton(text: s.addLogo) { model.add(.logo(LogoItem(logo: 1))) }
            if model.document?.concert != nil { BarButton(text: s.addMovie, action: pickers.addMovie) }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Fields commit on Enter, on a click elsewhere, or before any other edit; Esc puts the saved value back.
private struct Inspector: View {
    let model: AppModel
    let pickers: Pickers

    var body: some View {
        let s = model.strings
        VStack(alignment: .leading, spacing: 8) {
            field(model.document?.concert == nil ? s.movieTitle : s.concertTitle, .showTitle)
            logos(s)
            if let place = model.selection, let item = model.document?.item(at: place) {
                Palette.line.frame(height: 1)
                fields(place, item, s)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func logos(_ s: Strings) -> some View {
        if model.document?.concert == nil {
            Text(s.movieHasNoLogos).foregroundStyle(Palette.dim).lineLimit(2)
        } else {
            let logos = model.document?.logos ?? []
            ForEach(1...2, id: \.self) { number in
                let file = logos.indices.contains(number - 1) ? logos[number - 1] : nil
                HStack(spacing: 6) {
                    Text("\(s.logo) \(number)").foregroundStyle(Palette.dim).frame(width: 130, alignment: .leading)
                    BarButton(text: s.logoFile) { pickers.logoFile(number) }
                    Button {
                        model.setLogoFile(number, nil)
                    } label: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(Palette.dim)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(file == nil)
                    .opacity(file == nil ? 0.4 : 1)
                    Text(file?.url.lastPathComponent ?? s.noLogoFile)
                        .foregroundStyle(file == nil ? Palette.dim : Palette.fg)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    @ViewBuilder
    private func fields(_ place: Place, _ item: Item, _ s: Strings) -> some View {
        switch item {
        case .clip(let clip):
            field(s.clipTitle, .clipTitle(place), placeholder: Clip(file: clip.file).resolvedTitle)
            field(s.plannedEnd, .plannedEnd(place), placeholder: "m:ss")
            field(s.tail, .tail(place), placeholder: "m:ss")
        case .breakScreen(let item):
            field(s.breakText, .breakText(place), placeholder: s.breakTitle)
            field(s.breakMinutes, .breakMinutes(place))
            Toggle(isOn: Binding(get: { item.countdown }, set: { model.setCountdown(place, $0) })) {
                Text(s.countdown)
            }
            .toggleStyle(.checkbox)
            .focusable(false)
        case .logo(let logo):
            // Only logos the show has; a number above them would show black.
            let count = model.document?.logos.count ?? 0
            HStack(spacing: 6) {
                Text(s.logoNumber).foregroundStyle(Palette.dim).frame(width: 130, alignment: .leading)
                if count == 0 {
                    BarButton(text: "\(logo.logo)") {}.disabled(true).opacity(0.55)
                    Text(s.noLogos).foregroundStyle(Palette.warn).lineLimit(2)
                } else {
                    ForEach(1...count, id: \.self) { number in
                        BarButton(text: "\(number)") { model.edit(.setLogo(place, number)) }
                            .overlay {
                                if number == logo.logo {
                                    RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.armed, lineWidth: 2)
                                }
                            }
                    }
                }
            }
        case .movie:
            if let movie = model.selectedRow?.movie { field(s.movieTitle, .movieTitle(movie)) }
        case .black:
            Text(s.nothingToSet).foregroundStyle(Palette.dim)
        }
    }

    private func field(_ label: String, _ field: Field, placeholder: String = "") -> some View {
        EditField(model: model, label: label, field: field, placeholder: placeholder).id(field)
    }
}

private struct EditField: View {
    let model: AppModel
    let label: String
    let field: Field
    let placeholder: String
    @FocusState private var focused: Bool

    var body: some View {
        // Read here, not in the binding, so a revert or a saved change redraws the field.
        let text = model.draft(field)
        HStack(spacing: 10) {
            Text(label).foregroundStyle(Palette.dim).lineLimit(1).frame(width: 130, alignment: .leading)
            TextField(placeholder, text: Binding(get: { text }, set: { model.setDraft(field, $0) }))
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { model.commit(field) }
                .onChange(of: focused) { model.focusChanged(field, focused: focused) }
        }
    }
}

private struct CueRow: View {
    enum Role {
        case live, armed
    }

    let number: String
    let label: String
    let meta: String
    let blocked: Bool
    let role: Role?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.dim)
                .frame(minWidth: 24, alignment: .leading)
            Text(label).font(.system(size: 17)).lineLimit(1)
            if blocked { Circle().fill(Palette.live).frame(width: 10, height: 10) }
            Spacer(minLength: 8)
            Text(meta).font(.system(size: 14).monospacedDigit()).foregroundStyle(Palette.dim)
        }
        .padding(.vertical, 7)
        .padding(.leading, 16)
        .padding(.trailing, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background)
        .overlay(alignment: .leading) { bar.frame(width: 4) }
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
