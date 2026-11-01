// swift-tools-version: 6.0
import PackageDescription

// Built by CI on Swift 6.2, 6.3 and 6.4 (Debian). It lives outside the main package on purpose:
// `@nonexhaustive` diagnoses nothing inside the package that declares the enum, so this is the only
// place the "write @unknown default" requirement is checked. ConsumerExhaustive must fail to build.
let package = Package(
    name: "Consumer",
    platforms: [.macOS(.v15)],
    dependencies: [.package(name: "swift-kurrentdb", path: "../../..")],
    targets: [
        .target(name: "Consumer", dependencies: [.product(name: "KurrentDB", package: "swift-kurrentdb")]),
        .target(name: "ConsumerExhaustive", dependencies: [.product(name: "KurrentDB", package: "swift-kurrentdb")]),
    ]
)
