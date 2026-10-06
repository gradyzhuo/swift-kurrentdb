# Repository Guidelines

Short, verifiable facts about this repository for coding agents and new contributors. When in doubt, `Package.swift`, `CLAUDE.md` and `CONTRIBUTING.md` are the authorities.

## Project Structure & Module Organization
- `Sources/KurrentDB` — the public client (`KurrentDBClient`, target-based `Streams`, `Projections`, `PersistentSubscriptions`, `Users`, `Monitoring`, `Operations`, `Gossip`) plus the DocC catalog `KurrentDB.docc`.
- `Sources/KurrentDB_V1` — the deprecated 1.x flat-method API, kept for gradual migration.
- `Sources/KurrentDBPool` — lends clients for independent KurrentDB instances; entry point `withBorrowedClient(_:)`.
- `Sources/GRPCEncapsulates` — gRPC call-shape protocols (`UnaryUnary`, `UnaryStream`, `StreamUnary`, `StreamStream`) and request/response composition.
- `Sources/_GRPCProtobufGenerated` — code generated from `proto/`; never hand-edit.
- `Tests/<Area>Tests` — one Swift Testing target per area (`StreamsTests`, `ProjectionsTests`, `PersistentSubscriptionsTests`, `UsersTests`, `OperationsTests`, `MonitoringTests`, `GossipTests`, `KurrentCoreTests`, `MockClientTests`, `KurrentDBPoolTests`, `X509Tests`, `DocSnippetsTests`). Each suite owns its fixtures under `Resources/`.
- `Benchmarks/` and `scripts/` — benchmarks (swift-benchmark, results uploaded to Bencher) and helper scripts.
- `server/` — Docker Compose files for the local 3-node TLS cluster and the X.509 setup.
- `docs/adr/` — architecture decision records; `docs/superpowers/specs|plans` — design specs and implementation plans.
- `Package.resolved` is git-ignored: every toolchain resolves dependencies itself (Swift 6.0 resolves older grpc-swift versions than 6.2+ — see ADR 0001 and `Core/DeadlineCancellation.swift`).

## Build, Test, and Development Commands
- `swift build` — compile. `swift build --build-tests` also compiles every test target.
- Live tests need a KurrentDB cluster: `docker compose -f server/docker-compose.yaml up -d` (3 nodes, TLS, ports 2111–2113, admin/changeit). Wait until `docker ps` shows all three healthy.
- `swift test -v --no-parallel --disable-xctest --enable-swift-testing` — the full suite the way CI runs it. Suites are `.serialized`; keep `--no-parallel`.
- `swift test --filter StreamsTests` / `swift test --filter "LazyReadLiveTests|ResponseHandoffTests"` — a suite or a regex of suites. `MockClientTests` and `KurrentCoreTests` run offline (no cluster).
- `OperationsTests` runs as its own CI step after the main suites because it resigns the leader and restarts the persistent-subscriptions subsystem.
- `scripts/check-doc-snippets.sh` — compiles every ```` ```swift ```` block in `README.md`, the DocC articles and the `///` comments of `Sources/KurrentDB` and `Sources/KurrentDBPool` (via the git-ignored `Tests/DocSnippetsTests/DocSnippets.generated.swift`). Run it after touching any documentation example.
- Regenerating gRPC code: see `proto/README.md` (`swift package --allow-writing-to-package-directory generate-grpc-code-from-protos … --output-path Sources/_GRPCProtobufGenerated`). Commit the proto change and the regenerated sources together.
- Swift 6.0 compatibility check for a clean checkout: `docker run --rm --platform linux/arm64 -v "$PWD":/w -w /w swift:6.0-jammy swift build --build-tests` (use a fresh `git worktree`; a local `Package.resolved` would pin newer dependencies).

## Coding Style & Naming Conventions
- Swift 6 language mode, full data-race safety: no `@unchecked Sendable` in `Sources/`. Shared mutable state uses `Mutex` (Synchronization) or an actor.
- Formatting follows `.swiftformat` (`--swiftversion 6.0`, `--extensionacl on-declarations`). Four-space indentation, trailing commas in multi-line literals.
- `UpperCamelCase` types, `lowerCamelCase` members, expressive labels (`persistentSubscriptions(stream:group:)`, `append(events:configure:)`). Operation options are mutated in a trailing `inout` closure: `read { $0.limit = 10 }`.
- Usecases are named `Service.Operation` (`Streams.Read`, `Projections.ContinuousCreate`); behaviour differences between targets live in constrained extensions (`extension Streams where Target: SpecifiedStreamTarget`), not in runtime switches. Constrained extensions are statically dispatched — provide every entry point a generic caller may use.
- Access: `public` for the user-facing API, `package` for cross-module internals, `internal`/`private` otherwise. Generated files stay `package`.
- All `//` and `///` comments and all documentation are written in English.
- Typed throws: public operations `throws(KurrentError)`; wrap gRPC errors with `withRethrowingError(usage:)`.

## Testing Guidelines
- Swift Testing only (no XCTest): `@Suite("Name", .serialized)` structs, `@Test("behaviour in plain words") func name()`. Describe the behaviour in the test title; function names are `lowerCamelCase` (`earlyBreakReleasesLease`).
- Live suites build their `ClientSettings` as `ClientSettings.localhost(ports: 2111, 2112, 2113).secure(true).tlsVerifyCert(false).authenticated(.credentials(username: "admin", password: "changeit")).certificate(source: .crtInBundle("ca", inBundle: .module)!)`; the CA fixture is copied by the `.copy` resource directives in `Package.swift`.
- Prefer deterministic waits (a signal yielded by the code under test, or a bounded `eventually { … }` poll) over fixed sleeps; a fixed sleep is acceptable only for an upper-bound assertion that cannot false-fail.
- Tests that need extra infrastructure gate themselves: `X509Tests` (licensed node), `KurrentDBPoolLiveTests` (independent instances), `AppendRecordsTests` (`KURRENTDB_SUPPORTS_APPEND_RECORDS=true`).
- Add a regression test next to every bug fix, and verify it fails before the fix.

## Commit & Pull Request Guidelines
- Commit subjects use a bracketed tag and an English one-liner: `[ADD]`, `[UPDATE]`, `[FIX]`, `[REMOVE]`, `[REFACTOR]`, `[NEW]` — e.g. `[FIX] skip control frames on the lazy $all read like the buffered path`. No `Co-Authored-By:` trailers.
- Stage explicit paths; the working tree routinely holds untracked scratch files that must not be committed.
- A PR describes the change, the verification actually run (full suite, doc snippets, Swift 6.0 build when dependency behaviour is involved), any skipped or flaky tests, and any behaviour change that belongs in release notes. Large changes carry a spec under `docs/superpowers/specs/` and, for decisions that outlive the PR, an ADR under `docs/adr/`.
- CI (`.github/workflows/swift-build-testing.yml`) runs Swift 6.0–6.4 × KurrentDB 24.10–26.1 on a 3-node TLS cluster, offline builds on Amazon Linux and Debian, the pool live suite, and X.509 only when a license secret is present. Pull test images from `docker.kurrent.io`.

## Proto & Security Notes
- Proto sources live in `proto/` (`google/rpc`, `kurrent/rpc`, `kurrentdb/v1`, `kurrentdb/v2`). Regenerate with the `generate-grpc-code-from-protos` plugin as documented in `proto/README.md`; it needs network access the first time.
- Certificates under `Tests/*/Resources` and `server/` are test fixtures only. Never commit secrets, licence keys or production certificates; `server/vars.env` holds test defaults.
