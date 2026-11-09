// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cue",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CueCore"),
        .executableTarget(
            name: "CueApp",
            dependencies: ["CueCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(name: "CueCoreTests", dependencies: ["CueCore"]),
    ]
)
