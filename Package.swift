// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "EventStoreDB",
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "EventStoreDB",
            targets: ["EventStoreDB"]),
    ],
    dependencies: [
      .package(url: "https://github.com/grpc/grpc-swift.git", from: "1.15.0"),
      .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.6.0"),
    //   .package(url: "https://github.com/apple/swift-service-context.git",from: "1.0.0"),
      .package(url: "https://github.com/apple/swift-log.git", from: "1.0.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .executableTarget(
            name: "Run",
            dependencies: [
                .target(name: "EventStoreDB")
            ]),
        .target(
            name: "EventStoreDB",
            dependencies: [
                .product(name: "GRPC", package: "grpc-swift"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                // .product(name: "ServiceContextModule",package: "swift-service-context"),
                .product(name: "Logging", package: "swift-log")
            ],
            plugins: [
                .plugin(name: "GRPCSwiftPlugin", package: "grpc-swift"),
                .plugin(name: "SwiftProtobufPlugin", package: "swift-protobuf")
            ]),
        
        .testTarget(
            name: "EventStoreDBTests",
            dependencies: ["EventStoreDB"]),
    ]
)
