import Foundation

public enum CheckCommand: Equatable, Sendable {
    // No `--` option: start the app as usual.
    case app
    case check(path: String)
    case usage

    // EX_USAGE.
    public static let usageExitCode: Int32 = 64

    // `arguments` leaves out the program name. Only `--` options are ours, so macOS's single-dash flags pass through.
    public static func parse(_ arguments: [String]) -> CheckCommand {
        guard arguments.contains(where: { $0.hasPrefix("--") }) else { return .app }
        guard arguments.count == 2, arguments[0] == "--check", !arguments[1].isEmpty, !arguments[1].hasPrefix("--")
        else { return .usage }
        return .check(path: arguments[1])
    }

    public static func usage(program: String) -> String {
        """
        usage: \(program) --check <show>
          <show>: a .concert.json, a .movie.json or a clip folder (nothing is written)
          prints a JSON report on stdout
          exit 0 ok, 1 warnings, 2 blocked, 3 the show cannot be loaded, 64 bad arguments

        """
    }
}
