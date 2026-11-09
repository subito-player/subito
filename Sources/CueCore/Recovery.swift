import Foundation

public struct RecoveryState: Codable, Equatable, Sendable {
    // nil while no show is open.
    public var showPath: String?
    public var mode: Mode
    public var liveIndex: Int?
    public var livePosition: Double?
    public var cover: Cover?
    public var cleanExit: Bool
    // Consecutive recovered launches without a GO or a clean quit in between.
    public var recoveries: Int
    public var savedAt: Date

    public init(
        showPath: String?,
        mode: Mode,
        liveIndex: Int? = nil,
        livePosition: Double? = nil,
        cover: Cover? = nil,
        cleanExit: Bool,
        recoveries: Int = 0,
        savedAt: Date
    ) {
        self.showPath = showPath
        self.mode = mode
        self.liveIndex = liveIndex
        self.livePosition = livePosition
        self.cover = cover
        self.cleanExit = cleanExit
        self.recoveries = recoveries
        self.savedAt = savedAt
    }
}

public enum LaunchPlan: Equatable, Sendable {
    case open(String)
    // armIndex nil: nothing was live, so only the show and the mode come back.
    case recover(String, Mode, armIndex: Int?, at: Double)
    // Recovering crashed twice in a row: open the show and mode, arm nothing.
    case skipRecovery(String, Mode)
    case empty
}

public enum Recovery {
    public static let maxRecoveries = 2

    public static func plan(from state: RecoveryState?, launchArgument: String?) -> LaunchPlan {
        if let launchArgument {
            guard let state, !state.cleanExit, state.showPath == launchArgument else { return .open(launchArgument) }
            return recover(state, launchArgument)
        }
        guard let state, let path = state.showPath else { return .empty }
        return state.cleanExit ? .open(path) : recover(state, path)
    }

    // The count this launch writes: a recovery adds one, a skipped one keeps it, anything else starts over.
    public static func recoveries(for plan: LaunchPlan, from state: RecoveryState?) -> Int {
        switch plan {
        case .recover: (state?.recoveries ?? 0) + 1
        case .skipRecovery: state?.recoveries ?? 0
        case .open, .empty: 0
        }
    }

    // Missing and unreadable files both mean "nothing to recover".
    public static func load(from url: URL) -> RecoveryState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(RecoveryState.self, from: data)
    }

    public static func save(_ state: RecoveryState, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        var data = try encoder.encode(state)
        data.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func recover(_ state: RecoveryState, _ path: String) -> LaunchPlan {
        guard state.recoveries < maxRecoveries else { return .skipRecovery(path, state.mode) }
        return .recover(path, state.mode, armIndex: state.liveIndex, at: state.livePosition ?? 0)
    }
}
