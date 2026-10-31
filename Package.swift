// swift-tools-version:5.9
// Swift package for the platform-independent core (pitch detection, course data, scoring),
// so it can be tested with `swift test` without building the app.
import PackageDescription

let package = Package(
    name: "VocalCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "VocalCore", targets: ["VocalCore"]),
    ],
    targets: [
        .target(name: "VocalCore", path: "Sources/Core"),
        .testTarget(name: "VocalCoreTests", dependencies: ["VocalCore"], path: "Tests/VocalCoreTests"),
    ]
)
