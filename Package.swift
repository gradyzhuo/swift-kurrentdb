// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EventStoreDB",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EventStoreDB",
            targets: ["EventStoreDB"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.15.0"),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.6.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.8.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EventStoreDB",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "GRPCEncapsulates",
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .target(
            name: "GRPCEncapsulates",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
            ]
        ),
        .testTarget(
            name: "EventStoreDBTests",
            dependencies: [
                "EventStoreDB",
                .product(name: "Testing", package: "swift-testing")
            ],
            resources: [
                .copy("Resources/ca.crt"),
                .copy("Resources/multiple-events.json"),
            ]
        ),
        .testTarget(
            name: "GRPCEncapsulatesTests",
            dependencies: ["GRPCEncapsulates"]
        ),
    ]
)
