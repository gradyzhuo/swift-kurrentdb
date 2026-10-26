// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LiveBenchmarks",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "LiveDriverSwift", targets: ["LiveDriverSwift"]),
        .executable(name: "LiveOrchestrator", targets: ["LiveOrchestrator"]),
    ],
    dependencies: [
        .package(path: "../.."),
        .package(url: "https://github.com/HdrHistogram/hdrhistogram-swift", exact: "0.1.4"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "LiveBenchCore",
            dependencies: [.product(name: "Histogram", package: "hdrhistogram-swift")],
            path: "Sources/LiveBenchCore"
        ),
        .executableTarget(
            name: "LiveDriverSwift",
            dependencies: [
                "LiveBenchCore",
                .product(name: "KurrentDB", package: "swift-kurrentdb"),
                .product(name: "Histogram", package: "hdrhistogram-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "drivers/swift"
        ),
        .executableTarget(
            name: "LiveOrchestrator",
            dependencies: [
                "LiveBenchCore",
                .product(name: "KurrentDB", package: "swift-kurrentdb"),
                .product(name: "Histogram", package: "hdrhistogram-swift"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "orchestrator"
        ),
        .testTarget(
            name: "LiveBenchCoreTests",
            dependencies: ["LiveBenchCore"],
            path: "Tests/LiveBenchCoreTests"
        ),
        .testTarget(
            name: "LiveOrchestratorTests",
            dependencies: ["LiveOrchestrator", "LiveBenchCore"],
            path: "Tests/LiveOrchestratorTests"
        ),
    ]
)
