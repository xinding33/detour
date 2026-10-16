// swift-tools-version: 6.0
import PackageDescription

// No packages. Logic that can be tested without the hardware lives in DetourCore.
let package = Package(
    name: "Detour",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Detour", targets: ["Detour"])],
    targets: [
        .target(name: "DetourCore"),
        .executableTarget(name: "Detour", dependencies: ["DetourCore"]),
        .testTarget(name: "DetourCoreTests", dependencies: ["DetourCore"]),
    ]
)
