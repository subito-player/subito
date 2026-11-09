import Foundation

public let currentFormat = 1

public struct Movie: Codable, Equatable, Sendable {
    public var format: Int
    public var title: String
    public var colour: String?
    public var items: [Item]

    public init(format: Int = currentFormat, title: String, colour: String? = nil, items: [Item] = []) {
        self.format = format
        self.title = title
        self.colour = colour
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case format, title, colour, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        title = try container.decode(String.self, forKey: .title)
        colour = try container.decodeIfPresent(String.self, forKey: .colour)
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}

public struct Concert: Codable, Equatable, Sendable {
    public var format: Int
    public var title: String
    public var logos: [Logo]
    public var items: [Item]

    public init(format: Int = currentFormat, title: String, logos: [Logo] = [], items: [Item] = []) {
        self.format = format
        self.title = title
        self.logos = logos
        self.items = items
    }

    private enum CodingKeys: String, CodingKey {
        case format, title, logos, items
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decode(Int.self, forKey: .format)
        title = try container.decode(String.self, forKey: .title)
        logos = try container.decodeIfPresent([Logo].self, forKey: .logos) ?? []
        items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
    }
}

public enum Logo: Equatable, Sendable {
    case image(String)
    case loop(String)
}

extension Logo: Codable {
    private enum CodingKeys: String, CodingKey {
        case loop
    }

    public init(from decoder: Decoder) throws {
        if let path = try? decoder.singleValueContainer().decode(String.self) {
            self = .image(path)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self = .loop(try container.decode(String.self, forKey: .loop))
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .image(let path):
            var container = encoder.singleValueContainer()
            try container.encode(path)
        case .loop(let file):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(file, forKey: .loop)
        }
    }
}

public enum Item: Equatable, Sendable {
    case clip(Clip)
    case black
    case breakScreen(BreakItem)
    case logo(LogoItem)
    case movie(MovieRef)

    public var typeName: String {
        switch self {
        case .clip: "clip"
        case .black: "black"
        case .breakScreen: "break"
        case .logo: "logo"
        case .movie: "movie"
        }
    }
}

extension Item: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "clip": self = .clip(try Clip(from: decoder))
        case "black": self = .black
        case "break": self = .breakScreen(try BreakItem(from: decoder))
        case "logo": self = .logo(try LogoItem(from: decoder))
        case "movie": self = .movie(try MovieRef(from: decoder))
        case let other:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "unknown item type \"\(other)\"")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(typeName, forKey: .type)
        switch self {
        case .clip(let clip): try clip.encode(to: encoder)
        case .black: break
        case .breakScreen(let item): try item.encode(to: encoder)
        case .logo(let item): try item.encode(to: encoder)
        case .movie(let ref): try ref.encode(to: encoder)
        }
    }
}

public struct Clip: Codable, Equatable, Sendable {
    public var file: String
    public var number: Int?
    public var title: String?
    public var plannedEndS: Double?
    public var tailS: Double?
    public var colour: String?
    public var brief: String?

    private enum CodingKeys: String, CodingKey {
        case file, number, title, colour, brief
        case plannedEndS = "planned_end_s"
        case tailS = "tail_s"
    }

    public init(
        file: String,
        number: Int? = nil,
        title: String? = nil,
        plannedEndS: Double? = nil,
        tailS: Double? = nil,
        colour: String? = nil,
        brief: String? = nil
    ) {
        self.file = file
        self.number = number
        self.title = title
        self.plannedEndS = plannedEndS
        self.tailS = tailS
        self.colour = colour
        self.brief = brief
    }

    public var resolvedNumber: Int? {
        number ?? filenameParts.number
    }

    public var resolvedTitle: String {
        if let title { return title }
        let words = filenameParts.name.split(separator: "_")
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }

    // Splits "NN_name.ext" into (NN, "name"); no digit prefix leaves the whole stem as name.
    private var filenameParts: (number: Int?, name: String) {
        let stem = URL(fileURLWithPath: file).deletingPathExtension().lastPathComponent
        guard let underscore = stem.firstIndex(of: "_") else { return (nil, stem) }
        let prefix = stem[..<underscore]
        guard prefix.allSatisfy({ ("0"..."9").contains($0) }), let number = Int(prefix) else { return (nil, stem) }
        return (number, String(stem[stem.index(after: underscore)...]))
    }
}

public struct BreakItem: Codable, Equatable, Sendable {
    public var minutes: Double
    public var countdown: Bool
    public var text: String?

    private enum CodingKeys: String, CodingKey {
        case minutes, countdown, text
    }

    public init(minutes: Double, countdown: Bool = false, text: String? = nil) {
        self.minutes = minutes
        self.countdown = countdown
        self.text = text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        minutes = try container.decode(Double.self, forKey: .minutes)
        countdown = try container.decodeIfPresent(Bool.self, forKey: .countdown) ?? false
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }
}

public struct LogoItem: Codable, Equatable, Sendable {
    /// 1-based index into `Concert.logos`.
    public var logo: Int

    public init(logo: Int) {
        self.logo = logo
    }
}

public struct MovieRef: Codable, Equatable, Sendable {
    public var file: String

    public init(file: String) {
        self.file = file
    }
}
