// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShadowingPlayer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ShadowingPlayer", targets: ["ShadowingPlayer"])],
    targets: [
        .target(name: "ShadowingCore"),
        .executableTarget(name: "ShadowingPlayer", dependencies: ["ShadowingCore"]),
        .testTarget(name: "ShadowingCoreTests", dependencies: ["ShadowingCore", "ShadowingPlayer"])
    ]
)
