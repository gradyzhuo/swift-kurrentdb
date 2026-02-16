# Repository Guidelines

## Project Structure & Module Organization
Source targets live under `Sources/`: `KurrentDB` exposes the public client APIs, `_Streams` wraps GRPC streaming helpers, `GRPCEncapsulates` hosts low-level channel management, and `Generated` contains code emitted from .proto files—never hand-edit these outputs. Tests are grouped by concern (for example, `Tests/StreamsTests`, `Tests/ProjectionsTests`) and each suite owns any fixtures under its `Resources/` folder. Reusable protobuf definitions and the regeneration script are in `proto/`, while top-level metadata (`Package.swift`, `Package.resolved`, `README.md`) describes the SwiftPM package.

## Build, Test, and Development Commands
- `swift build` compiles the package for the current platform; pass `--configuration release` before cutting a tag.
- `swift test` runs the full XCTest suite; target a subset via `swift test --filter StreamsTests/BackwardReads`.
- `swift package generate-xcodeproj` lets you inspect code in Xcode if you prefer that workflow.
- `bash proto/generate.sh` refreshes the gRPC stubs after editing files in `proto/kurrentdb` or `proto/google`; commit both `Sources/GRPCEncapsulates/Generated` and the proto changes.

## Coding Style & Naming Conventions
Follow idiomatic Swift 6: four-space indentation, trailing commas for multi-line literals, and `UpperCamelCase` for types such as `KurrentDBClient`. Use `lowerCamelCase` for methods (`appendStream`) and properties, and prefer expressive argument labels (`subscribePersistentSubscription(stream:groupName:)`). Keep module imports explicit and avoid wildcard extensions. Generated files stay package-visible; do not change their access modifiers outside the generator.

## Testing Guidelines
All logic additions must include XCTests in the closest suite (for example, stream projections belong in `Tests/ProjectionsTests`). Name tests descriptively using the `test<Scenario>_<Expectation>()` convention to align with current files. Since the suite hits TLS fixtures, ensure `Resources/ca.crt` is included via the `.copy` directives already defined in `Package.swift`. Run `swift test --enable-code-coverage` locally for regressions touching networking or serialization.

## Commit & Pull Request Guidelines
Recent history uses bracketed prefixes (e.g., `[UPDATE] refine persistent subscription errors`). Continue that style with concise, one-line summaries. Each pull request should: describe the change set, mention affected modules (`Sources/KurrentDB`, `Tests/StreamsTests`, etc.), link to any GitHub issues, and include screenshots or logs when modifying observable behavior. Re-run `swift build` and `swift test` before requesting review, and call out any flaky or skipped tests explicitly.

## Proto & Security Notes
When regenerating gRPC bindings, run `bash proto/generate.sh` from a machine that already has `protoc` installed; the script clones plugins on demand, so ensure network access is available. Never check secrets into `proto/` resources, and treat TLS certificates under `Tests/*/Resources` as fixtures only—replace them if you need to reproduce production-like scenarios.
