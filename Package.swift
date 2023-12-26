// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "EventStoreDB",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EventStoreDB",
            targets: ["EventStoreDB", "GRPCSupport"])
    ],
    dependencies: [
      .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.15.0"),
      .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.6.0"),
      .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "EventStoreDB",
            dependencies: [
                .product(name: "Logging", package: "swift-log"),
                "GRPCSupport"
            ]),
        .target(
            name: "GRPCSupport",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf")
            ],
            plugins: [
                .plugin(name: "GRPCSwiftPlugin", package: "grpc-swift"),
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")
            ]),
        .executableTarget(name: "GRPCTesting", dependencies: [
            .target(name: "EventStoreDB")
            ]),
        .testTarget(
            name: "EventStoreDBTests",
            dependencies: ["EventStoreDB"]),
    ]
)
