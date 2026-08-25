// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-kurrentdb",
    // Platform minimums are set to the first OS versions that shipped Swift 6 concurrency
    // features required by this package (structured concurrency, typed throws, ~Copyable).
    // macOS 15, iOS 18, tvOS 18, watchOS 11, visionOS 2.
    //
    // Linux is supported on Swift 6.0+ without any OS-version restriction.
    // Swift Package Manager does not accept a `.linux` entry here; Linux support
    // is implicit when no Apple-only frameworks are used. All imports in this
    // package (Foundation, GRPCNIOTransportHTTP2Posix, Synchronization, NIO)
    // are available on Linux.
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
        .library(
            name: "KurrentDB_V1",
            targets: [
                "KurrentDB_V1",
            ]
        ),
        .library(
            name: "KurrentDBPool",
            targets: [
                "KurrentDBPool",
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
            name: "KurrentDB_V1",
            dependencies: [
                "KurrentDB",
            ]
        ),
        .target(
            name: "KurrentDBPool",
            dependencies: [
                "KurrentDB",
                .product(name: "GRPCCore", package: "grpc-swift-2"),
            ]
        ),
        .target(
            name: "GRPCEncapsulates",
            dependencies: [
                .product(name: "GRPCCore", package: "grpc-swift-2"),
                .product(name: "GRPCNIOTransportHTTP2", package: "grpc-swift-nio-transport"),
                "_GRPCProtobufGenerated"
            ]
        ),
        .target(
            name: "_GRPCProtobufGenerated",
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
        .testTarget(
            name: "OperationsTests",
            dependencies: [
                "KurrentDB",
            ],
            resources: [
                .copy("Resources/ca.crt"),
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
        // MockClientTests: offline unit tests using MockKurrentDBClient.
        // No live server required — only factory call patterns are verified.
        .testTarget(
            name: "MockClientTests",
            dependencies: [
                "KurrentDB",
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
            name: "KurrentDBPoolTests",
            dependencies: [
                "KurrentDB",
                "KurrentDBPool",
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

