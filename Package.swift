// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LightQuickLook",
    platforms: [.macOS(.v26)],
    products: [.library(name: "LightQuickLookCore", targets: ["LightQuickLookCore"])],
    targets: [
        .target(name: "LightQuickLookCore", path: "LightQuickLookCore"),
        .executableTarget(name: "LightQuickLookSelfTest", dependencies: ["LightQuickLookCore"], path: "Scripts/LightQuickLookSelfTest"),
        .executableTarget(name: "LightQuickLookBenchmark", dependencies: ["LightQuickLookCore"], path: "Scripts/LightQuickLookBenchmark"),
        .testTarget(name: "LightQuickLookCoreTests", dependencies: ["LightQuickLookCore"], path: "LightQuickLookTests")
    ]
)
