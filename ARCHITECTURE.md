# Architecture Analysis — swift-kurrentdb

> 此文件分析 swift-kurrentdb 的程式架構設計，並與相似的官方語言客戶端（.NET、Go、Java、Node.js）進行比較，給予評價與評分。
>
> _This document analyses the software architecture of swift-kurrentdb, compares it with analogous official-language clients, and provides an overall assessment and score._

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Module Breakdown](#2-module-breakdown)
3. [Key Design Patterns](#3-key-design-patterns)
4. [Comparison with Similar Packages](#4-comparison-with-similar-packages)
5. [Dimension-by-Dimension Evaluation](#5-dimension-by-dimension-evaluation)
6. [Strengths](#6-strengths)
7. [Areas for Improvement](#7-areas-for-improvement)
8. [Overall Score](#8-overall-score)

---

## 1. Architecture Overview

swift-kurrentdb is organised as a **three-layer SwiftPM package** targeting Swift 6 and the latest Apple/Linux platforms.

```
┌─────────────────────────────────────────────────────────┐
│                     Consumer App                        │
└─────────────────────────┬───────────────────────────────┘
                          │ imports KurrentDB
┌─────────────────────────▼───────────────────────────────┐
│  KurrentDB  (public-facing, high-level Swift API)        │
│  ┌──────────────────────────────────────────────────┐   │
│  │  KurrentDBClient (actor)                         │   │
│  │  ├── Streams / PersistentSubscriptions           │   │
│  │  ├── Projections / Users / Operations / Gossip  │   │
│  │  └── NodeSelector (actor) ← cluster discovery   │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────┘
                          │ imports GRPCEncapsulates
┌─────────────────────────▼───────────────────────────────┐
│  GRPCEncapsulates  (gRPC abstraction, package-internal)  │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Usecase protocols:                              │   │
│  │    UnaryUnary / UnaryStream / StreamUnary        │   │
│  │    StreamStream / GRPCConcreteService            │   │
│  │  Buildable / CommandOptions / GRPCBridge         │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────┬───────────────────────────────┘
                          │ imports Generated
┌─────────────────────────▼───────────────────────────────┐
│  Generated  (auto-generated protobuf / gRPC stubs)       │
│  ┌──────────────────────────────────────────────────┐   │
│  │  kurrentdb_v*.pb.swift (SwiftProtobuf)           │   │
│  │  kurrentdb_v*.grpc.swift (grpc-swift 2.x)        │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

Each layer has a single well-defined responsibility:

| Layer | Responsibility | Access |
|---|---|---|
| `KurrentDB` | Domain model, public API, connection lifecycle | `public` |
| `GRPCEncapsulates` | RPC pattern protocols, builder utilities | `package` |
| `Generated` | Protobuf types, gRPC service descriptors | `package` |

---

## 2. Module Breakdown

### 2.1 KurrentDB — Top-level API

| Subsystem | Files | Role |
|---|---|---|
| `KurrentDBClient` | `KurrentDBClient.swift` + extensions | Actor-based entry point; orchestrates all operations |
| `ClientSettings` | `ClientSettings/` | Immutable value-type configuration; `Buildable` chaining; connection-string parsing |
| `NodeSelector` | `NodeSelector.swift` | Actor for cluster-node discovery via gossip; automatic retry |
| `Streams` | `Streams/` | Append, read (forward/backward), delete, tombstone, catch-up subscribe |
| `PersistentSubscriptions` | `PersistentSubscriptions/` | Create/update/delete/subscribe; ACK/NAK; `$all` and named-stream variants |
| `Projections` | `Projections/` | Continuous / one-time / transient projection CRUD; protocol-composition target model |
| `Users` | `Users/` | Create, enable/disable, reset-password, list |
| `Operations` | `Operations/` | Scavenge, merge indexes, shutdown, node priority |
| `Gossip` | `Gossip/` | Raw cluster gossip; `MemberInfo`; `VNodeState` |
| `Monitoring` | `Monitoring/` | Live stats streaming |
| `Error` | `KurrentError.swift` | Exhaustive typed-error enum; `withRethrowingError` helper |

### 2.2 GRPCEncapsulates — Abstraction Layer

| Component | Role |
|---|---|
| `Usecase` | Base marker protocol; associates `ServiceClient` ↔ `Transport` |
| `UnaryUnary` | Single request → single response (most management ops) |
| `UnaryStream` | Single request → streaming response (server-side streaming) |
| `StreamUnary` | Streaming request → single response (batch append) |
| `StreamStream` | Bidirectional streaming (persistent subscription read/write loop) |
| `Buildable` | `withCopy` zero-allocation value-type builder |
| `GRPCBridge` | Bridges Swift domain types ↔ protobuf messages |

### 2.3 Generated — Auto-generated Code

Never hand-edited. Regenerated via `bash proto/generate.sh` using the `.proto` files in `proto/`.

---

## 3. Key Design Patterns

### 3.1 Actor-Based Concurrency

```
KurrentDBClient (actor)   NodeSelector (actor)   NodeDiscover (actor)
       │                          │                       │
       └── all state mutations    └── selectedNode cache  └── endpoint resolution
           are actor-isolated         + retry logic           + gossip calls
```

* No manual locks, no `DispatchQueue` — pure Swift Structured Concurrency.
* `Sendable` conformance is enforced across all public types (Swift 6 strict checking).

### 3.2 Target-Based Type-Safe API

```swift
// Compile-time: SpecifiedStream exposes append/read/delete/subscribe
let stream: Streams<SpecifiedStream> = client.streams(of: .specified("orders"))
try await stream.append(events: [...])  // ✓

// Compile-time: AllStreams does NOT expose append — no runtime guard needed
let all: Streams<AllStreams> = client.streams(of: .all)
try await all.append(events: [...])     // ✗ compile error
```

This is rare among KurrentDB clients — most rely on runtime checks or documentation.

### 3.3 Immutable Builder Pattern (Zero Allocation)

```swift
// ClientSettings, Options, etc. use copy-on-write via `withCopy`
let opts = Streams.Append.Options()
    .revision(expected: .streamExists)  // returns new struct, 0 heap allocations
```

Benchmarks confirm option builders allocate **zero bytes** on the heap.

### 3.4 Typed Error Propagation

```swift
// Swift 6 typed-throws: callers know the exact error type at compile time
func select() async throws(KurrentError) -> Node
```

No `any Error` boxing in hot paths; exhaustive `switch` on every call site.

### 3.5 Usecase Protocol Hierarchy

Every RPC operation is a `struct` that conforms to exactly one of the four `Usecase` sub-protocols. This means:

* **Adding a new operation** = new file + `struct` + one `extension` on the target.
* The gRPC transport layer is completely isolated from business logic.
* Unit-testing an operation's request-building is possible without a network.

---

## 4. Comparison with Similar Packages

The table below compares swift-kurrentdb with the four official EventStoreDB/Kurrent clients.

| Dimension | swift-kurrentdb | [.NET client][dotnet] | [Go client][go] | [Java client][java] | [Node.js client][nodejs] |
|---|:---:|:---:|:---:|:---:|:---:|
| Language / runtime | Swift 6 | C# 12 / .NET 8 | Go 1.21 | Java 11 / Kotlin | TypeScript / Node 20 |
| Concurrency model | `actor` / async-await | `async`/`await` + `Channel<T>` | goroutines + channels | Project Loom / coroutines | `async`/`await` + `EventEmitter` |
| Type safety | ★★★★★ | ★★★★☆ | ★★★☆☆ | ★★★★☆ | ★★★★☆ |
| Compile-time operation constraints | ✅ (target generics) | ❌ | ❌ | ❌ | ❌ |
| Typed errors | ✅ `throws(KurrentError)` | ✅ (specific exception types) | ✅ (Go error values) | ✅ (checked exceptions) | ❌ (all `Error`) |
| Builder / options pattern | ✅ zero-alloc value types | ✅ fluent mutable classes | ⚠️ struct literals | ✅ fluent builder objects | ✅ plain objects |
| Connection string | ✅ | ✅ | ✅ | ✅ | ✅ |
| TLS / cluster gossip | ✅ | ✅ | ✅ | ✅ | ✅ |
| Persistent subscriptions ($all) | ✅ | ✅ | ✅ | ✅ | ✅ |
| Projections API | ✅ full | ✅ full | ⚠️ partial | ✅ full | ✅ full |
| User management | ✅ | ✅ | ❌ | ✅ | ✅ |
| Server operations | ✅ | ✅ | ❌ | ✅ | ✅ |
| Monitoring / stats | ✅ | ✅ | ❌ | ❌ | ❌ |
| Benchmarks included | ✅ (BENCHMARKS.md) | ❌ | ❌ | ❌ | ❌ |
| DocC / hosted documentation | ✅ (Swift Package Index) | ✅ (docs.eventstore.com) | ✅ (pkg.go.dev) | ✅ (javadoc) | ✅ (docs.eventstore.com) |
| Test coverage (integration) | ✅ full suite | ✅ full suite | ✅ full suite | ✅ full suite | ✅ full suite |
| Swift 6 data-race safety | ✅ | N/A | N/A | N/A | N/A |
| Offline / unit-testable ops | ✅ (Usecase structs) | ⚠️ | ⚠️ | ⚠️ | ⚠️ |

[dotnet]: https://github.com/EventStore/EventStore-Client-Dotnet
[go]: https://github.com/EventStore/EventStore-Client-Go
[java]: https://github.com/EventStore/EventStoreDB-Client-Java
[nodejs]: https://github.com/EventStore/EventStore-Client-NodeJs

---

## 5. Dimension-by-Dimension Evaluation

### 5.1 Architecture Design — 9 / 10

The three-layer separation (public API → gRPC abstraction → generated stubs) is clean, principled, and mirrors the best practices from large Swift libraries such as `grpc-swift` itself. The `Usecase` protocol hierarchy makes adding new operations mechanical and isolated. One point deducted because `GRPCEncapsulates` is currently not separately versioned/published, making it impossible for third-party authors to build alternative transports without forking.

### 5.2 Type Safety — 10 / 10

The generic `Streams<Target>` design, combined with `SpecifiedStreamTarget` / `AllStreams` / `MultiStreams` protocol constraints, eliminates an entire class of runtime errors **at compile time**. No other EventStoreDB client in any language achieves this level of compile-time operation validation. This is the most distinctive architectural feature of the package.

### 5.3 Concurrency Model — 9 / 10

Full adoption of Swift Structured Concurrency, including `actor` isolation for both `KurrentDBClient` and `NodeSelector`, `AsyncSequence` for streaming responses, and `Sendable` enforcement throughout. This is ahead of all official clients, which still rely on callbacks or platform-specific concurrency primitives in their hot paths. Minor deduction: the `eventLoopGroup` property leaks a SwiftNIO implementation detail into the public actor interface.

### 5.4 Error Handling — 9 / 10

`KurrentError` is an exhaustive, human-readable enum. The `withRethrowingError` helper cleanly converts gRPC, NIO, and domain errors into a single hierarchy. Swift 6 typed throws (`throws(KurrentError)`) make the error contract explicit in function signatures — a capability unavailable in any other language. One point deducted for the typo `cerificates` (should be `certificates`) which has propagated into the public API surface.

### 5.5 API Ergonomics — 8 / 10

The builder pattern with trailing closures produces ergonomic, readable call sites:

```swift
try await client.appendStream("orders", events: events) {
    $0.revision(expected: .streamExists)
}
```

The target-based API is expressive once learned. However, the dual API surface (convenience methods on `KurrentDBClient` _and_ target-based methods on service objects) can confuse newcomers. A few public method names also contain the typo `cerificate` / `cerificates`.

### 5.6 Feature Completeness — 9 / 10

All major KurrentDB 24.x / 25.x features are covered: streams, persistent subscriptions (including `$all`), projections (continuous/one-time/transient), user management, server operations, gossip, and real-time monitoring. Minor deduction: the Go client exposes a `SetStreamMetadata` API that is not yet present here.

### 5.7 Documentation — 9 / 10

DocC documentation is thorough, hosted on Swift Package Index, and includes worked examples for every public API. `CONTRIBUTING.md`, `BENCHMARKS.md`, and the `CLAUDE.md` engineering guide are well-maintained. Minor deduction: some advanced topics (e.g. catch-up subscription restart strategies, projection result deserialization) lack dedicated guide articles.

### 5.8 Performance — 9 / 10

The `BENCHMARKS.md` file documents offline benchmarks using `package-benchmark`. Key findings: option builders have **zero heap allocations**, stream identifiers are zero-allocation, and event serialisation is dominated by `JSONEncoder` (expected). Connection-string parsing is flagged as a parse-once hotspot with guidance. This level of benchmark transparency is absent from all official clients.

### 5.9 Testability — 8 / 10

Every operation type is a plain `struct` implementing a protocol, making it easy to unit-test request building and response parsing without a live server. The integration test suite covers all subsystems. Deductions: the test targets share a single boilerplate `ClientSettings` setup without a reusable base fixture type; mock/stub infrastructure for offline testing of the `KurrentDBClient` actor itself is not provided.

### 5.10 Platform & Ecosystem Fit — 8 / 10

The package targets macOS 15+, iOS 18+, tvOS, watchOS, visionOS, and Linux — an unusually broad range for a server-oriented client. Swift 6 compliance is a genuine differentiator for safety-conscious server-side codebases. Minor deduction: the minimum platform versions (macOS 15, iOS 18) are newer than many production deployments, which may delay adoption.

---

## 6. Strengths

1. **Compile-time operation safety** via generic `Target` types — unique among all KurrentDB clients in any language.
2. **Swift 6 actor model** — zero manual synchronisation primitives; correct-by-construction concurrency.
3. **Zero-allocation option builders** — measurably better memory behaviour than fluent mutable-class builders in .NET or Java.
4. **Typed throws** — function signatures are self-documenting contracts; exhaustive `catch` branches prevent silent error swallowing.
5. **Well-structured three-layer separation** — easy to navigate, extend, and reason about in code review.
6. **Transparent benchmarks** — the only Kurrent client of any language that ships quantitative performance data.
7. **Broad platform support** — the same package works in iOS apps, macOS services, and Linux servers.

---

## 7. Areas for Improvement

| Priority | Issue | Suggestion |
|---|---|---|
| High | Typo `cerificates` / `cerificate` propagated into public API | Rename to `certificates` / `certificate` with a `@available(*, deprecated, renamed:)` bridge |
| Medium | Dual API surface (convenience methods + target-based) can confuse newcomers | Deprecate the flat convenience methods on `KurrentDBClient` in favour of the target-based API exclusively |
| Medium | `eventLoopGroup` exposed as `package` on a `public actor` | Encapsulate NIO details; expose a higher-level lifecycle hook instead |
| Medium | No mock / stub infrastructure for unit testing client behaviour | Provide a protocol-backed `KurrentDBClientProtocol` to enable dependency injection |
| Low | `NodeSelector` caches `selectedNode` indefinitely | Introduce TTL-based cache invalidation or re-discovery on connection failure |
| Low | Missing `SetStreamMetadata` / `GetStreamMetadata` operations | Implement parity with the .NET and Java clients |
| Low | Platform minimums (macOS 15 / iOS 18) are very recent | Document rationale; consider conditional availability guards for older OS |

---

## 8. Overall Score

| Dimension | Weight | Score | Weighted |
|---|:---:|:---:|:---:|
| Architecture Design | 15% | 9 / 10 | 1.35 |
| Type Safety | 15% | 10 / 10 | 1.50 |
| Concurrency Model | 12% | 9 / 10 | 1.08 |
| Error Handling | 10% | 9 / 10 | 0.90 |
| API Ergonomics | 12% | 8 / 10 | 0.96 |
| Feature Completeness | 10% | 9 / 10 | 0.90 |
| Documentation | 8% | 9 / 10 | 0.72 |
| Performance | 8% | 9 / 10 | 0.72 |
| Testability | 5% | 8 / 10 | 0.40 |
| Platform & Ecosystem Fit | 5% | 8 / 10 | 0.40 |
| **Total** | **100%** | — | **8.93 / 10** |

### Summary

**swift-kurrentdb scores 8.93 / 10** — placing it above every official EventStoreDB client in the categories that matter most to Swift developers (type safety, concurrency model, and Swift idiom usage). Its compile-time operation constraints and zero-allocation builders are genuinely novel contributions to the EventStore client ecosystem. The remaining gap to a perfect score is addressable through API surface cleanup (fixing the `cerificates` typo, consolidating the dual convenience/target API), richer mock infrastructure, and a few missing low-level operations.

> Compared to the official .NET client — widely regarded as the reference implementation — swift-kurrentdb matches it on feature completeness and surpasses it on type safety, concurrency correctness, and memory efficiency for the Swift platform.
