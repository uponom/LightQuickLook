// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuickSourceLook",
    platforms: [.macOS(.v15)],
    products: [.library(name: "QuickSourceCore", targets: ["QuickSourceCore"])],
    targets: [
        .target(name: "QuickSourceCore", path: "QuickSourceCore"),
        .executableTarget(name: "QuickSourceSelfTest", dependencies: ["QuickSourceCore"], path: "Scripts/QuickSourceSelfTest"),
        .executableTarget(name: "QuickSourceBenchmark", dependencies: ["QuickSourceCore"], path: "Scripts/QuickSourceBenchmark"),
        .testTarget(name: "QuickSourceCoreTests", dependencies: ["QuickSourceCore"], path: "QuickSourceTests")
    ]
)
