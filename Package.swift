// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SandboxWatch",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "SandboxWatchKit", targets: ["SandboxWatchKit"]),
        .executable(name: "sbw", targets: ["sbw"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        .target(name: "SandboxWatchKit", dependencies: ["Yams"]),
        .executableTarget(name: "sbw", dependencies: [
            "SandboxWatchKit",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        // "sbw" too: the CLI makes its own decisions (argument validation, the shape of the
        // printed table) that deserve the same coverage as the Kit, exactly as HomePortManager
        // tests its `hpm` target.
        .testTarget(name: "SandboxWatchKitTests", dependencies: ["SandboxWatchKit", "sbw"]),
    ]
)
