// swift-tools-version: 6.0
// The repository's helper scripts: one executable per script, sharing the Tooling library,
// run as `swift run --package-path scripts <name> …` from the repository root.
import PackageDescription

let scripts = ["doc-versions", "build-docs-site", "generate-doc-snippets", "check-release-readiness", "bench-to-bmf"]

let package = Package(
    name: "scripts",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "Tooling"),
        .testTarget(name: "ToolingTests", dependencies: ["Tooling"]),
    ] + scripts.map { .executableTarget(name: $0, dependencies: ["Tooling"]) }
)
