// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "StressTest",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .target(
            name: "StressTest",
            dependencies: [
                .product(name: "KurrentDB", package: "swift-kurrentdb")
            ],
            path: "Sources/StressTest"
        ),
        .executableTarget(
            name: "stress-test",
            dependencies: [
                .target(name: "StressTest")
            ],
            path: "Sources/Main"
        ),
        .testTarget(
            name: "StressTestTests",
            dependencies: [
                .target(name: "StressTest"),
                .product(name: "KurrentDB", package: "swift-kurrentdb")
            ],
            path: "Tests"
        )
    ]
)
