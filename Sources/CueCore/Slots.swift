import Foundation

// Pictures 1 and 2 are Logo 1 and 2, pictures 3 to 8 are slots 1 to 6; a cover shows picture n as `.logo(n)`.
public let pictureCount = 8
public let logoCount = 2
public let slotCount = pictureCount - logoCount

public struct SlotEntry: Codable, Equatable, Sendable {
    public var name: String
    public var file: String

    public init(name: String, file: String) {
        self.name = name
        self.file = file
    }

    // A video file loops muted; anything else shows as an image.
    public var logo: Logo {
        Logo(
            name: name, path: file,
            loops: ShowLoader.playableExtensions.contains(URL(fileURLWithPath: file).pathExtension.lowercased()))
    }
}

// A concert's change to one slot of the default set.
public enum SlotOverride: Equatable, Sendable {
    case useDefault
    case empty
    case own(SlotEntry)
}

extension SlotOverride: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .useDefault
        } else if let text = try? container.decode(String.self) {
            guard text.isEmpty else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "a slot is null, \"\" or { \"name\": ..., \"file\": ... }")
            }
            self = .empty
        } else {
            self = .own(try container.decode(SlotEntry.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .useDefault: try container.encodeNil()
        case .empty: try container.encode("")
        case .own(let entry): try container.encode(entry)
        }
    }
}

// The default set saved on this Mac, absolute paths; nil or an empty path is an empty picture.
public struct SlotSet: Codable, Equatable, Sendable {
    public var format: Int
    // Logo 1 and 2.
    public var logos: [Logo?]
    // Slots 1 to 6.
    public var slots: [SlotEntry?]

    public init(format: Int = currentFormat, logos: [Logo?] = [], slots: [SlotEntry?] = []) {
        self.format = format
        self.logos = logos
        self.slots = slots
    }

    private enum CodingKeys: String, CodingKey {
        case format, logos, slots
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        logos = try container.decodeIfPresent([Logo?].self, forKey: .logos) ?? []
        slots = try container.decodeIfPresent([SlotEntry?].self, forKey: .slots) ?? []
    }

    public static let fileName = "slots.json"

    // Missing is the empty set; a broken file is the empty set plus the reason, and stays on disk untouched.
    public static func load(from url: URL) -> (set: SlotSet, error: ShowError?) {
        guard FileManager.default.fileExists(atPath: url.path) else { return (SlotSet(), nil) }
        do {
            return (try ShowLoader.decode(SlotSet.self, from: url), nil)
        } catch {
            return (SlotSet(), error as? ShowError ?? .fileMissing(url))
        }
    }

    // Timestamped, so a later move-aside never replaces an earlier broken file.
    public static func brokenURL(for url: URL, at date: Date) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = url.deletingPathExtension().lastPathComponent
        return url.deletingLastPathComponent().appendingPathComponent(
            "\(name).broken-\(formatter.string(from: date)).json")
    }

    // Atomic; overBroken first moves the broken file aside (returned), so a save never loses the owner's text.
    @discardableResult
    public func save(to url: URL, overBroken: Bool, now: Date = Date()) throws -> URL? {
        let files = FileManager.default
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var aside: URL?
        if overBroken, files.fileExists(atPath: url.path) {
            let target = Self.brokenURL(for: url, at: now)
            // moveItem refuses an existing target, so nothing already set aside is ever replaced.
            try files.moveItem(at: url, to: target)
            aside = target
        }
        try ShowLoader.write(self, to: url)
        return aside
    }

    // The default set has nothing under it, so .useDefault and .empty both clear the picture.
    public mutating func setPicture(_ number: Int, _ change: SlotOverride) {
        guard (1...pictureCount).contains(number) else { return }
        let entry: SlotEntry? = if case .own(let own) = change, !own.file.isEmpty { own } else { nil }
        if number <= logoCount {
            while logos.count < number { logos.append(nil) }
            logos[number - 1] = entry?.logo
        } else {
            let index = number - logoCount - 1
            while slots.count <= index { slots.append(nil) }
            slots[index] = entry
        }
        while let last = logos.last, last == nil { logos.removeLast() }
        while let last = slots.last, last == nil { slots.removeLast() }
    }
}

public enum PictureSource: Equatable, Sendable {
    case defaultSet, concert
}

public struct Picture: Equatable, Sendable {
    public var name: String
    public var file: LogoFile
    public var source: PictureSource

    public init(name: String, file: LogoFile, source: PictureSource) {
        self.name = name
        self.file = file
        self.source = source
    }
}

// Where the picture inspector saves the next change.
public enum PictureScope: Equatable, Sendable {
    case thisConcert, everyConcert
}

// One picture inspector change; a new name or file keeps the other field of the picture shown now.
public enum PictureChange: Equatable, Sendable {
    case name(String)
    case file(String)
    case empty
}

// What one inspector change saves; nil leaves that side as it is.
public struct PictureWrite: Equatable, Sendable {
    public var defaultSet: SlotOverride?
    public var concert: SlotOverride?

    public init(defaultSet: SlotOverride? = nil, concert: SlotOverride? = nil) {
        self.defaultSet = defaultSet
        self.concert = concert
    }
}

extension Concert {
    // This concert's own setting for picture n; a logo reads like a slot.
    public func pictureOverride(_ number: Int) -> SlotOverride {
        if number <= logoCount {
            guard logos.indices.contains(number - 1), let logo = logos[number - 1] else { return .useDefault }
            return logo.path.isEmpty ? .empty : .own(SlotEntry(name: logo.name, file: logo.path))
        }
        let index = number - logoCount - 1
        return slots.indices.contains(index) ? slots[index] : .useDefault
    }
}

public enum Pictures {
    // nil when there is nothing to write: a name for a picture with no file.
    // Every concert includes this one, so it also drops this concert's own setting and the change shows at once.
    public static func write(
        _ change: PictureChange, to number: Int, shown: Picture?, concert: Concert?, scope: PictureScope
    ) -> PictureWrite? {
        let stored = concert?.pictureOverride(number) ?? .useDefault
        let override: SlotOverride
        switch change {
        case .empty:
            override = .empty
        case .name(let name):
            guard let shown else { return nil }
            var file = shown.file.url.path
            // As the concert wrote it, so a relative path outside the show folder stays relative.
            if scope == .thisConcert, shown.source == .concert, case .own(let own) = stored { file = own.file }
            override = .own(SlotEntry(name: name, file: file))
        case .file(let file):
            override = .own(SlotEntry(name: shown?.name ?? "", file: file))
        }
        switch scope {
        case .thisConcert:
            return PictureWrite(concert: override)
        case .everyConcert:
            return PictureWrite(defaultSet: override, concert: stored == .useDefault ? nil : .useDefault)
        }
    }

    // Back to default has work to do: the concert has its own file, or "" over the default.
    public static func concertOverrides(_ number: Int, in concert: Concert?) -> Bool {
        (concert?.pictureOverride(number) ?? .useDefault) != .useDefault
    }

    // Empty this slot only where the scope has something to clear; Every concert clears this concert too.
    public static func canEmpty(
        _ number: Int, shown: Picture?, defaults: SlotSet, concert: Concert?, scope: PictureScope
    ) -> Bool {
        switch scope {
        case .thisConcert:
            return shown != nil
        case .everyConcert:
            let fromDefault = entry(merge(defaults: defaults, concert: nil, concertURL: nil), number - 1)
            return fromDefault != nil || concertOverrides(number, in: concert)
        }
    }

    // Always `pictureCount` entries, nil where nothing shows; concert paths resolve against the concert file.
    public static func merge(defaults: SlotSet, concert: Concert?, concertURL: URL?) -> [Picture?] {
        func picture(_ logo: Logo?, _ source: PictureSource) -> Picture? {
            guard let logo, !logo.path.isEmpty else { return nil }
            let base = source == .concert ? concertURL : nil
            let url = base.map { ShowLoader.resolve(logo.path, relativeTo: $0) } ?? URL(fileURLWithPath: logo.path)
            return Picture(name: logo.name, file: logo.loops ? .loop(url) : .image(url), source: source)
        }
        let logos = (0..<logoCount).map { index -> Picture? in
            if let concert, concert.logos.indices.contains(index), let own = concert.logos[index] {
                return picture(own, .concert)
            }
            return picture(entry(defaults.logos, index), .defaultSet)
        }
        let slots = (0..<slotCount).map { index -> Picture? in
            let change = concert.flatMap { $0.slots.indices.contains(index) ? $0.slots[index] : nil } ?? .useDefault
            switch change {
            case .useDefault: return picture(entry(defaults.slots, index)?.logo, .defaultSet)
            case .empty: return nil
            case .own(let own): return picture(own.logo, .concert)
            }
        }
        return logos + slots
    }

    // The same in both languages, so preflight details can carry it.
    public static func slotName(_ picture: Picture?, number: Int) -> String {
        let name = picture?.name ?? ""
        return name.isEmpty ? "Slot \(number - logoCount)" : name
    }

    private static func entry<T>(_ list: [T?], _ index: Int) -> T? {
        list.indices.contains(index) ? list[index] : nil
    }
}
