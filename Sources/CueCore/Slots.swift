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

public enum Pictures {
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

    private static func entry<T>(_ list: [T?], _ index: Int) -> T? {
        list.indices.contains(index) ? list[index] : nil
    }
}
