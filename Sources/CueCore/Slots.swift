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
        ShowLoader.playableExtensions.contains(URL(fileURLWithPath: file).pathExtension.lowercased())
            ? .loop(file) : .image(file)
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

public enum PictureWrite: Equatable, Sendable {
    case concert(SlotOverride)
    case defaultSet(SlotOverride)
}

public enum Pictures {
    // nil when there is nothing to write: a name for a logo, or for a picture with no file.
    public static func write(_ change: PictureChange, to number: Int, shown: Picture?, scope: PictureScope)
        -> PictureWrite?
    {
        let isSlot = number > logoCount
        let override: SlotOverride
        switch change {
        case .empty:
            override = .empty
        case .name(let name):
            guard isSlot, let shown else { return nil }
            override = .own(SlotEntry(name: name, file: shown.file.url.path))
        case .file(let file):
            override = .own(SlotEntry(name: isSlot ? shown?.name ?? "" : "", file: file))
        }
        return scope == .thisConcert ? .concert(override) : .defaultSet(override)
    }

    // Always `pictureCount` entries, nil where nothing shows; concert paths resolve against the concert file.
    public static func merge(defaults: SlotSet, concert: Concert?, concertURL: URL?) -> [Picture?] {
        func picture(_ name: String, _ logo: Logo?, _ source: PictureSource) -> Picture? {
            guard let logo, !logo.path.isEmpty else { return nil }
            let base = source == .concert ? concertURL : nil
            let url = base.map { ShowLoader.resolve(logo.path, relativeTo: $0) } ?? URL(fileURLWithPath: logo.path)
            let file: LogoFile = if case .loop = logo { .loop(url) } else { .image(url) }
            return Picture(name: name, file: file, source: source)
        }
        let logos = (0..<logoCount).map { index -> Picture? in
            let name = "Logo \(index + 1)"
            if let concert, concert.logos.indices.contains(index), let own = concert.logos[index] {
                return picture(name, own, .concert)
            }
            return picture(name, entry(defaults.logos, index), .defaultSet)
        }
        let slots = (0..<slotCount).map { index -> Picture? in
            let change = concert.flatMap { $0.slots.indices.contains(index) ? $0.slots[index] : nil } ?? .useDefault
            switch change {
            case .useDefault: return entry(defaults.slots, index).flatMap { picture($0.name, $0.logo, .defaultSet) }
            case .empty: return nil
            case .own(let own): return picture(own.name, own.logo, .concert)
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
