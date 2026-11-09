import Foundation

public enum LaunchArguments {
    // macOS and Xcode inject `-psn_*` and `-key value` pairs (`-AppleLanguages (hu)`), which are never the show.
    public static func showPath(_ arguments: [String]) -> String? {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            guard argument.hasPrefix("-") else { return argument }
            index += argument.hasPrefix("-psn_") ? 1 : 2
        }
        return nil
    }
}
