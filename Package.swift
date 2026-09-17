// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Conch", platforms: [.macOS("27.0")],
    products: [.executable(name: "Conch", targets: ["Conch"])],
    targets: [
        .target(name: "Realtime", publicHeadersPath: "include"),
        .executableTarget(
            name: "Conch", dependencies: ["Realtime"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "ConchTests", dependencies: ["Conch", "Realtime"]),
    ])
