// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "KurrentDB-Swift",
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
            name: "EventStoreDB",
            targets: [
                "EventStoreDB",
            ]
        ),
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
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EventStoreDB",
            dependencies: [
                "KurrentDB",
            ]
        ),
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
                .product(name: "GRPCProtobuf", package: "grpc-swift-protobuf"),
            ]
        ),
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
    ]
)
