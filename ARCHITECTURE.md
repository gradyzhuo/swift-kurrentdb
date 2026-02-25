# Architecture Analysis

This document analyses the design of `swift-kurrentdb`, identifies areas for improvement,
and benchmarks the library against comparable clients in other ecosystems.

---

## Module Structure

The package is split into four modules with clear separation of concerns:

```
swift-kurrentdb
├── KurrentDB            Public API — consumer-facing
│   ├── Core/            Connection settings, error types, domain primitives
│   ├── Streams/         Stream operations (append, read, subscribe, delete)
│   ├── Projections/     Projection management
│   ├── PersistentSubscriptions/
│   ├── Users/
│   ├── Monitoring/
│   ├── Operations/
│   └── Gossip/
├── KurrentDB_V1         Backwards-compatible convenience wrappers
├── GRPCEncapsulates     gRPC abstraction — Usecase protocols (package-internal)
└── Generated            Auto-generated protobuf/gRPC bindings (do not edit)
```

### Layer Responsibilities

| Layer | Role | Access |
|---|---|---|
| `KurrentDB` | Consumer API, business logic, domain types | `public` |
| `KurrentDB_V1` | Backwards-compatible convenience aliases | `public` |
| `GRPCEncapsulates` | Usecase patterns, transport abstraction | `package` |
| `Generated` | Auto-generated gRPC/protobuf types | `package` |

The dependency graph flows in one direction only: `KurrentDB` → `GRPCEncapsulates` → `Generated`. `KurrentDB_V1` depends only on `KurrentDB`, so it can never reach the transport layer directly. This strict layering makes it straightforward to swap the transport without touching public APIs.

---

## Key Design Patterns

### 1. Target-Based API (Compile-Time Operation Safety)

The most distinctive design choice is the **target** system. Rather than overloaded methods or string-based routing, each resource scope is a distinct Swift type:

```swift
public func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target>
```

Available operations are expressed as conditional extensions on `Streams<Target>`, so calling an invalid operation is a *compile error*, not a runtime exception:

```swift
// SpecifiedStreamTarget supports append, read, delete, subscribe
extension Streams where Target: SpecifiedStreamTarget {
    public func append(events: [EventData], options: ...) async throws(KurrentError) -> ...
    public func read(options: ...) async throws(KurrentError) -> ...
}

// AllStreams only exposes read and subscribe — no append method exists
extension Streams where Target == AllStreams {
    public func read(options: ...) async throws(KurrentError) -> ...
    public func subscribe(options: ...) async throws(KurrentError) -> ...
    // append(...) does not exist here → compile error if attempted
}
```

This is more expressive than the official EventStoreDB .NET and Java clients, which both rely on method overloads or runtime guards to separate operations on `$all` from operations on named streams.

### 2. Usecase Protocol Hierarchy

`GRPCEncapsulates` defines four protocols that mirror gRPC call patterns:

```
Usecase
├── UnaryUnary    (single request → single response)
├── UnaryStream   (single request → streaming response)
├── StreamUnary   (streaming request → single response)
└── StreamStream  (bidirectional streaming)
```

Each operation (e.g. `Streams.Append`, `Streams.Read`) conforms to the appropriate protocol. This cleanly decouples *what* an operation does from *how* it is transported, and makes adding new operations mechanical — implement the protocol, wire up the request/response mapping, done.

### 3. Zero-Allocation Builder Pattern

Options are configured via a copy-on-write `Buildable` protocol backed by value types:

```swift
extension Buildable {
    func withCopy(handler: (_ copied: inout Self) -> Void) -> Self {
        var copiedSelf = self
        handler(&copiedSelf)
        return copiedSelf
    }
}
```

Because `Options` types are structs, all builder chains operate entirely on the stack. The benchmarks confirm **zero heap allocations** for any builder chain of arbitrary length, which is a meaningful advantage over fluent-builder APIs based on reference types (such as the .NET client's `AppendToStreamOptions`).

### 4. Actor-Based Concurrency

| Type | Isolation |
|---|---|
| `Streams<Target>` | `actor` — protects mutable `selector` reference |
| `NodeSelector` | `actor` — caches the selected node and expiry |
| `NodeDiscover` | `actor` — manages gossip state |
| `KurrentDBClient` | `struct + Sendable` — holds immutable references to actors |

The library achieves full Swift 6 `Sendable` compliance. All public methods use typed throws (`throws(KurrentError)`), a feature introduced in Swift 5.9/6.0 that enforces a single, predictable error type at the call site.

### 5. Gossip-Based Cluster Discovery

`NodeDiscover` implements the EventStoreDB gossip protocol to locate the optimal node based on `NodePreference` (`.leader`, `.follower`, `.readOnlyReplica`, `.random`). The result is cached in `NodeSelector` for 30 seconds to avoid discovery overhead on every call.

---

## Identified Issues

| Severity | Description | Location |
|---|---|---|
| **Medium** | `fatalError` inside `ExpressibleByStringLiteral` — an invalid connection string crashes the process in production instead of propagating an error | `ClientSettings.swift` — `init(stringLiteral:)` |
| **Low** | Typo: query parameter key `"connectionanme"` should be `"connectionname"` — causes connection name to be silently ignored when set via a connection string | `ClientSettings.swift` — `parse(connectionString:)` |
| **Low** | The 30-second node-cache TTL in `NodeSelector` is hardcoded — it should be driven by a `ClientSettings` property so callers can tune it | `NodeSelector.swift:37` |
| **Low** | Duplicate documentation blocks on `getMetadata()` — three copies of the summary comment were accidentally left in the source | `Streams.swift:120–152` |
| **Info** | `KurrentDBClient.shutdown()` shuts down the *client-side* event loop group, but the name conceptually conflicts with the server-side `Operations.shutdown()` call; a rename (e.g. `close()`) would remove the ambiguity | `KurrentDBClient.swift:207` |

---

## Comparison with Similar Clients

### Official EventStoreDB / Kurrent Clients

| Feature | **swift-kurrentdb** | .NET client | Java client | Go client | Node.js client |
|---|---|---|---|---|---|
| Language | Swift 6 | C# 12 | Java 17 | Go 1.21 | TypeScript 5 |
| Async model | `async/await` + actors | `async/await` + `Task<T>` | Reactor / `CompletableFuture` | goroutines + channels | `async/await` |
| Type-safe operation scoping | ✅ Generics + conditional extensions | ❌ Method overloads | ❌ Method overloads | ❌ Explicit function calls | ❌ Method overloads |
| Typed errors | ✅ `throws(KurrentError)` | ❌ Exception hierarchy | ❌ Exception hierarchy | ❌ Go error interface | ❌ Generic `Error` |
| Zero-alloc builder pattern | ✅ Value-type `withCopy` | ❌ Reference-type fluent | ❌ Builder classes | ✅ Functional options | ❌ Plain objects |
| Cluster gossip discovery | ✅ | ✅ | ✅ | ✅ | ✅ |
| TLS / certificate config | ✅ | ✅ | ✅ | ✅ | ✅ |
| Connection string | ✅ | ✅ | ✅ | ✅ | ✅ |
| Persistent subscriptions | ✅ | ✅ | ✅ | ✅ | ✅ |
| Projections API | ✅ Full | ✅ Full | ⚠️ Partial | ❌ | ✅ Full |
| Users / ACL API | ✅ | ✅ | ❌ | ❌ | ✅ |
| Monitoring / stats | ✅ | ✅ | ❌ | ❌ | ❌ |
| Cluster gossip read | ✅ | ✅ | ❌ | ❌ | ❌ |
| Offline benchmarks | ✅ Documented | ❌ | ❌ | ❌ | ❌ |
| Data-race safety | ✅ Swift 6 | ⚠️ Partial | ⚠️ Partial | ✅ (channels) | ❌ |
| gRPC backend | `grpc-swift` 2.x | `grpc-dotnet` | `grpc-java` | `grpc-go` | `@grpc/grpc-js` |

### Comparable Swift Database Drivers

| Feature | **swift-kurrentdb** | `vapor/postgres-nio` | `mongodb/mongo-swift-driver` | `vapor/redis` |
|---|---|---|---|---|
| Swift 6 concurrency | ✅ Full | ✅ Full | ⚠️ Partial | ⚠️ Partial |
| Actor-isolated service types | ✅ | ✅ | ⚠️ | ❌ |
| Typed errors | ✅ `throws(KurrentError)` | ❌ | ❌ | ❌ |
| Protocol-based design depth | ✅ Rich (4-tier protocol hierarchy) | ✅ Rich | ✅ Medium | ❌ Simple |
| DocC documentation | ✅ Full | ✅ Full | ✅ Full | ⚠️ Sparse |
| Offline benchmarks | ✅ | ❌ | ❌ | ❌ |
| CI on Linux | ✅ | ✅ | ✅ | ✅ |
| Backwards-compat layer | ✅ `KurrentDB_V1` | N/A | N/A | N/A |

---

## Evaluation and Scores

| Category | Score | Notes |
|---|---|---|
| **API Design** | 9 / 10 | The target-based type system is genuinely novel for a database client — compile-time operation safety is a clear step beyond every official EventStoreDB client. The only friction is the extra `.streams(of:)` wrapper for everyday access. |
| **Concurrency Safety** | 9 / 10 | Full Swift 6 `Sendable` compliance; proper actor isolation throughout. The only concern is the hardcoded 30-second node-cache TTL. |
| **Error Handling** | 7 / 10 | Typed throws at every public API boundary is excellent. The `fatalError` path in the connection-string string-literal initialiser is a significant production risk that lowers this score. |
| **Documentation** | 8 / 10 | Comprehensive DocC, BENCHMARKS.md, CONTRIBUTING.md, and a detailed README. Duplicate doc-comment blocks in `Streams.swift` and a slightly out-of-date project structure in CONTRIBUTING.md are minor blemishes. |
| **Test Coverage** | 7 / 10 | Solid per-feature integration test suites. Offline unit tests for the connection-string parser, options builders, and error-mapping paths are missing; these could catch regressions without requiring a running server. |
| **Performance** | 9 / 10 | Zero-allocation builders; benchmarks are tracked and documented. The `JSONEncoder()` hot-path for event serialisation (~8.6 µs, 15 allocations) is normal; connection-string parsing (~324–397 µs) is documented as a parse-once concern. |
| **Feature Completeness** | 9 / 10 | Projections + Users + Gossip + Monitoring + Persistent Subscriptions — broader coverage than most official clients (the Java and Go clients, in particular, do not expose projections or user management). |
| **Maintainability** | 8 / 10 | Clean module layering; strict one-direction dependency graph; consistent naming. The typo in the connection-string parser key and the hardcoded TTL are small but actionable improvements. |

### Overall: **8.25 / 10**

`swift-kurrentdb` is the most type-safe EventStoreDB client across any language ecosystem, and arguably the best-designed Swift 6 database driver currently available. The target-based generic API and zero-allocation builder pattern set a high bar. Addressing the `fatalError` in `init(stringLiteral:)` and adding offline unit tests for the parser and options layers would bring the score to 9+.

---

## Recommended Next Steps

1. **Fix `fatalError` in string-literal connection-string parsing** — either remove `ExpressibleByStringLiteral` conformance (use `try ClientSettings.parse(connectionString:)` explicitly) or swap `fatalError` for a logged no-op that falls back to `.localhost()`.
2. **Fix the `"connectionanme"` typo** in the connection-string parser so the `connectionName` parameter is correctly honoured.
3. **Make node-cache TTL configurable** — add a `nodeSelectionCacheDuration: Duration` property to `ClientSettings` and thread it through to `NodeSelector`.
4. **Add offline unit tests** for `ClientSettings.parse(connectionString:)`, all `Options` builders, and `KurrentError` mapping to guard against parser regressions without needing a server.
5. **Resolve the `shutdown()` naming ambiguity** — consider renaming `KurrentDBClient.shutdown()` to `close()` to distinguish it from the server-side operation.
