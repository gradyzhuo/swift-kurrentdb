// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-kurrentdb",
    platforms: [
        .macOS(.v15),
        .iOS(.v18),
        .tvOS(.v18),
        .watchOS(.v11),
        .visionOS(.v2),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "KurrentDB",
            targets: [
                "KurrentDB",
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift-2.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-nio-transport.git", from: "2.0.0"),
        .package(url: "https://github.com/grpc/grpc-swift-protobuf.git", from: "2.0.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.33.3"),
    ] + {
        #if os(macOS)
        return [Package.Dependency.package(url: "https://github.com/ordo-one/package-benchmark.git", from: "1.22.0")]
        #else
        return []
        #endif
    }(),
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "KurrentDB",
            dependencies: [
                "GRPCEncapsulates",
                .product(name: "Logging", package: "swift-log"),
            ]
        ),
        .target(
            name: "GRPCEncapsulates",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                "Generated",
            ]
        ),
        .target(
            name: "Generated",
            dependencies: [
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        // Benchmarks are macOS-only — package-benchmark requires jemalloc on Linux.
        // Use the dedicated benchmark workflow to run these locally or on macOS CI.
    ] + {
        #if os(macOS)
        return [Target.executableTarget(
            name: "OfflineBenchmarks",
            dependencies: [
                "KurrentDB",
                .product(name: "Benchmark", package: "package-benchmark"),
            ],
            path: "Benchmarks/OfflineBenchmarks",
            plugins: [
                .plugin(name: "BenchmarkPlugin", package: "package-benchmark"),
            ]
        )]
        #else
        return []
        #endif
    }() + [
        .testTarget(
            name: "KurrentCoreTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
        .testTarget(
            name: "StreamsTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
        .testTarget(
            name: "ProjectionsTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
        .testTarget(
            name: "PersistentSubscriptionsTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
        .testTarget(
            name: "UsersTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
        .testTarget(
            name: "GossipTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
        .testTarget(
            name: "MonitoringTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ],
            swiftSettings: [
                .unsafeFlags([
                    "-Xfrontend",
                    "-warn-long-function-bodies=100",
                    "-Xfrontend",
                    "-warn-long-expression-type-checking=100",
                ]),
            ]
        ),
    ]
)

