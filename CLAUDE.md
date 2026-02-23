# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

KurrentDB-Swift is a modern, type-safe Swift client for Kurrent (formerly EventStoreDB), designed for Event Sourcing applications in Server-Side Swift. The package is built on top of grpc-swift 2.x and uses Swift Concurrency (async/await) with full Swift 6 data-race safety compliance.

**Key Links:**
- Documentation: https://swiftpackageindex.com/gradyzhuo/KurrentDB-Swift/documentation/kurrentdb
- GitHub: https://github.com/gradyzhuo/KurrentDB-Swift

## Build & Testing Commands

### Build
```bash
swift build
```

### Build with Tests
```bash
swift build --build-tests --enable-code-coverage
```

### Run All Tests
```bash
swift test
```

### Run Tests (Swift Testing framework, no XCTest)
```bash
swift test -v --no-parallel --disable-xctest --enable-swift-testing
```

### Run Specific Test Suite
```bash
swift test --filter StreamsTests
swift test --filter ProjectionsTests
swift test --filter PersistentSubscriptionsTests
swift test --filter KurrentCoreTests
```

### Run Single Test
```bash
swift test --filter StreamTests/testAppendEvent
```

## Development Requirements

- **Swift:** 6.0 or later
- **Platforms:** macOS 15+, iOS 18+, tvOS 18+, watchOS 11+, visionOS 2+
- **Kurrent Server:** 24.2+ (or EventStoreDB 23.10+)
- **Testing:** Requires a running Kurrent/EventStoreDB instance on localhost:2113 (insecure mode)

For local testing, use Docker:
```bash
docker run --rm -d -p 2113:2113 \
  -e KURRENTDB_CLUSTER_SIZE=1 \
  -e KURRENTDB_RUN_PROJECTIONS=All \
  -e KURRENTDB_START_STANDARD_PROJECTIONS=true \
  -e KURRENTDB_INSECURE=true \
  -e KURRENTDB_ENABLE_ATOM_PUB_OVER_HTTP=true \
  docker.kurrent.io/kurrent-latest/kurrentdb:25.1
```

## Architecture

### Three-Layer Architecture

The codebase is organized into three distinct module layers:

#### 1. KurrentDB (High-Level API)
- **Location:** `Sources/KurrentDB/`
- **Purpose:** Public-facing Swift API for interacting with Kurrent/EventStoreDB
- **Entry Point:** `KurrentDBClient` (actor-based, thread-safe)
- **Key Components:**
  - `Streams` - Stream operations (append, read, delete, subscribe)
  - `Projections` - Projection management (create, update, enable, disable)
  - `PersistentSubscriptions` - Persistent subscription operations
  - `Users` - User management
  - `Monitoring` - Cluster health monitoring
  - `Operations` - Server operations (scavenges, etc.)

#### 2. GRPCEncapsulates (Abstraction Layer)
- **Location:** `Sources/GRPCEncapsulates/`
- **Purpose:** Abstracts gRPC patterns into reusable Swift protocols
- **Key Protocols:**
  - `Usecase` - Base protocol for all RPC operations
  - `UnaryUnary` - Request-response RPC pattern
  - `UnaryStream` - Request-streaming response pattern
  - `StreamUnary` - Streaming request-response pattern
  - `StreamStream` - Bidirectional streaming pattern
  - `GRPCConcreteService` - Service abstraction
  - `Buildable` - Builder pattern support

#### 3. Generated (Protocol Buffers)
- **Location:** `Sources/Generated/`
- **Purpose:** Auto-generated gRPC and protobuf code from `.proto` files
- **Do Not Edit:** These files are generated from protobuf definitions

### Key Design Patterns

#### Target-Based API Design
The API uses a "target" pattern to provide type-safe access to different resource scopes:

```swift
// Stream targets
client.streams(of: .specified(name: "orders"))  // Specific stream
client.streams(of: .all)                        // $all stream

// Projection targets
client.projections(name: "my-projection")       // Named projection
client.projections(system: .byCategory)         // System projection
client.projections(all: .continuous)            // All continuous projections
```

#### Actor-Based Concurrency
- `KurrentDBClient` is an `actor` for thread-safe state management
- `NodeSelector` is an `actor` for cluster node selection
- All operations use Swift Concurrency (async/await)

#### Builder Pattern with Trailing Closures
Options are configured using a builder pattern with trailing closures:

```swift
try await client.appendStream("orders", events: events) {
    $0.revision(expected: .streamExists)
}

let events = try await client.readStream("orders") {
    $0.backward().startFrom(revision: .end).maxCount(10)
}
```

#### Node Selection & Connection Management
- `NodeSelector` handles cluster discovery via gossip protocol
- `NodeDiscover` finds the best node based on `NodePreference` (leader/follower/random)
- Automatic reconnection with configurable retry intervals
- TLS/SSL support with certificate verification

### Connection Settings

`ClientSettings` configures the client behavior:

```swift
// Localhost (insecure)
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))

// Cluster with gossip discovery
let settings = ClientSettings(clusterMode: .seeds([
    .init(host: "node1", port: 2113),
    .init(host: "node2", port: 2113)
]))
```

**Cluster Modes:**
- `.standalone(Endpoint)` - Single node
- `.dns(Endpoint)` - DNS discovery
- `.seeds([Endpoint])` - Gossip-based cluster discovery

## Source Code Organization

```
Sources/
├── KurrentDB/                   # Main library
│   ├── KurrentDBClient.swift    # Primary entry point (actor)
│   ├── Core/                    # Core types and utilities
│   │   ├── ClientSettings/      # Connection configuration
│   │   ├── NodeSelector.swift   # Cluster node selection
│   │   └── Additions/Usecase/   # Usecase extensions (UnaryUnary, etc.)
│   ├── Streams/                 # Stream operations
│   │   ├── Usecase/
│   │   │   ├── Specified/       # Single stream operations
│   │   │   └── All/             # $all stream operations
│   │   └── StreamTarget.swift   # Target abstraction
│   ├── Projections/             # Projection management
│   │   ├── Usecase/Create/      # Create operations by mode
│   │   └── Protocols/           # ProjectionTarget protocol & extensions
│   ├── PersistentSubscriptions/ # Persistent subscriptions
│   │   └── Usecase/
│   │       ├── AllStream/       # $all subscriptions
│   │       └── Specified/       # Stream-specific subscriptions
│   ├── Users/                   # User management
│   ├── Monitoring/              # Health checks
│   ├── Operations/              # Server operations
│   └── Gossip/                  # Cluster gossip protocol
├── GRPCEncapsulates/            # gRPC abstraction layer
│   ├── Usecase/                 # RPC pattern protocols
│   ├── GRPCConcreteService.swift
│   └── Buildable.swift
└── Generated/                   # Auto-generated protobuf/gRPC code
    └── kurrentdb_v*.pb.swift    # Generated from .proto files

Tests/
├── StreamsTests/                # Stream operation tests
├── ProjectionsTests/            # Projection management tests
├── PersistentSubscriptionsTests/# Persistent subscription tests
└── KurrentCoreTests/            # Core functionality tests
```

## Testing

- Tests use the **Swift Testing** framework (not XCTest)
- Test suites are marked with `@Suite` and use `.serialized` execution
- Tests require authentication: `admin:changeit`
- All test suites extend from base patterns that configure `ClientSettings.localhost()`

Example test pattern:
```swift
@Suite("Stream Tests", .serialized)
struct StreamTests: Sendable {
    let settings: ClientSettings

    init() {
        settings = .localhost()
            .authenticated(.credentials(username: "admin", password: "changeit"))
    }

    @Test("Test description")
    func testName() async throws {
        let client = KurrentDBClient(settings: settings)
        // Test logic
    }
}
```

## Protobuf Code Generation

The `Sources/Generated/` directory contains auto-generated code from `.proto` files. If protobuf definitions change:

1. Update `.proto` files in the protobuf source directory
2. Regenerate Swift code using protoc with grpc-swift plugins
3. Do not manually edit generated files

## Important Conventions

### Package Access Control
- Use `package` access modifier for internal APIs shared between modules
- Use `public` for user-facing APIs
- Most implementation details are `package` or `private(set)`

### Error Handling
- Custom error type: `KurrentError`
- Uses Swift's typed throws: `throws(KurrentError)`
- Helper: `withRethrowingError(usage:)` wraps operations and converts errors

### Logging
- Uses `swift-log` framework
- Logger available via `logger` global instance
- Log connection lifecycle, node selection, and RPC operations

### Naming Conventions
- Usecases follow pattern: `ServiceName.Operation` (e.g., `Streams.Append`, `Projections.Create`)
- Extensions separate by target type (e.g., `Projections+ContinuousMode.swift`)
- Protocol composition for capabilities (e.g., `ProjectionCreatable`, `ProjectionDeletable`)

## CI/CD

GitHub Actions workflow (`.github/workflows/swift-build-testing.yml`):
- Tests against Swift 6.0, 6.1, 6.2
- Runs on Ubuntu with KurrentDB container
- Enables code coverage reporting to Codecov
- Uses Swift Testing framework with parallel execution disabled

## Workflow Orchestration
### 1. Plan Node Default
- Enter plan mode for ANY non-trivial task (3+ steps or architectural decisions)
- If something goes sideways, STOP and re-plan immediately - don't keep pushing
- Use plan mode for verification steps, not just building
- Write detailed specs upfront to reduce ambiguity
### 2. Subagent Strategy
- Use
subagents liberally to keep main context window clean
- Offload research, exploration, and parallel analysis to subagents
- For complex problems, throw more compute at it via subagents
- One tack per subagent for focused execution
### 3. Self-Improvement Loop
- After ANY correction from the user: update "tasks/lessons.md" with the pattern
- Write rules for yourself that prevent the same mistake
- Ruthlessly iterate on these lessons until mistake rate drops
- Review lessons at session start for relevant project
### 4. Verification Before Done
- Never mark a task complete without proving it works
- Diff behavior between main and your changes when relevant
- Ask yourself: "Would a staff engineer approve this?"
- Run tests, check logs, demonstrate correctness
### 5. Demand Elegance (Balanced)
- For non-trivial changes: pause and ask "is there a more elegant way?"
- If a fix feels hacky: "Knowing everything I know now, implement the elegant solution"
- Skip this for simple, obvious fixes - don't over-engineer
- Challenge your own work before presenting it
### 6. Autonomous Bug Fizing
- When given a bug report: just fix it. Don't ask for hand-holding
- Point at logs, errors, failing tests - then resolve them
- Zero context switching required from the user
- Go fix failing CI tests without being told how
## Task Management
1. **Plan First**: Write plan to "tasks/todo.md" with checkable items
tasks/lessons.md" after corrections
## Core Principles
- **Simplicity First**: Make every change as simple as possible. Impact minimal code.
- **No Laziness**: Find root causes. No temporary fixes. Senior developer standards.
- **Minimat Impact**: Changes should only touch what's necessary. Avoid introducing bugs.

2. **Verify Plan**: Check in before starting implementation

3. **Track Progress**: Mark items complete as you go

4. **Explain Changes**: High-level summary at each step

5. **Document Results**: Add review section to 'tasks/todo.md"

6. **Capture Lessons**: Update
