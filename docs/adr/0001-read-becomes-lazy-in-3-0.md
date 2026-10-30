# ADR 0001 — `read()` delivers events lazily in 3.0

- Status: accepted (2026-10-06); amended 2026-10-31
- Applies to: `Streams.read(configure:)` on specified streams and `$all`
- Related: `docs/superpowers/specs/2026-10-06-read-call-lazy-buffered-design.md`, security audit 2026-10-04 item S02 (PR #148 was the superseded first attempt);
  amendment: `docs/superpowers/specs/2026-10-28-release-3-0-design.md` (§2 S-table, §4 U1/U4, §5.1, §5.7), issue #191
- Amendment 2026-10-31 (the 3.0 outcome, PR B): decision 2 resolved; the 2.x deprecation step recorded as skipped;
  consequence 4 corrected; the silent changes S2, S5 and S6 recorded; "3.0 amendment: the hand-off" added; the
  2.x overload-resolution limitation removed. Text written on 2026-10-06 is kept; additions are marked *Amended 2026-10-31*.

## Context

Since 1.12.0 (the grpc-swift 2 migration, commit `125ccef6`), `read()` drains the whole RPC
response into an unbounded `AsyncThrowingStream` before returning it. The caller gets a stream
whose RPC has already finished, at the cost of memory proportional to the result size. The
design was intentional: "when the read loop is done, the connection is closed" was the property
the author wanted, and a stream handed out lazily could not promise it.

The `feat/read-call-lazy-buffered` branch adds a bounded, backpressured hand-off (`ResponseHandoff`) and a `ReadCall` descriptor
with two explicit delivery modes:

```swift
for try await r in stream.read().lazy { … }                 // backpressured; RPC closes when the iterator is released
for try await r in try await stream.read().buffered { … }   // whole result first; identical to today's read()
for try await r in try await stream.read() { … }            // existing form, kept and not deprecated in 2.x
```

In 2.x the existing `read()` keeps its buffered behaviour so that no existing code changes
meaning or type.

## Decision

In **3.0** the default delivery of `read()` becomes **lazy**: iterating pulls events from the
server as they are consumed, memory per read is bounded by the hand-off (one element, held by the
suspended producer), the transport's inbound message queue (10 messages by default) and one HTTP/2
stream flow-control window (about 8 MiB by default), not by the result size, and the RPC ends when the iterator is released (loop finished, `break`,
`throw`, or task cancellation). Code that needs the whole result up front writes `.buffered`
explicitly.

Consequences for 3.0:

1. The overload `read(configure:) async throws -> AsyncThrowingStream<Read.Response, Error>` is
   removed. `read(configure:)` returns `ReadCall` only.
2. Either `ReadCall` conforms to `AsyncSequence` with lazy semantics (so `.lazy` becomes optional
   and `for try await r in stream.read()` is the idiomatic form), or iteration stays explicit via
   `.lazy` / `.buffered`. This choice is deferred to the 3.0 planning; both are compatible with the
   2.x shape because `ReadCall` deliberately does **not** conform to `AsyncSequence` in 2.x.

   *Amended 2026-10-31 — resolved (owner, 2026-10-28, U4):* `ReadCall` conforms to `AsyncSequence`
   (`Element = Streams.ReadResponse`, `Failure = any Error`, `makeAsyncIterator() -> Streams.ReadCall.Iterator`,
   a non-`Sendable` `final class`), so `for try await r in stream.read()` is the idiomatic form.
   `read(configure:)` is synchronous and non-throwing. `.lazy` stays as a deprecated no-op through 3.x
   (`@available(*, deprecated, message: "read() is lazy in 3.0; drop .lazy. Removed in 4.0.") public var lazy: ReadCall { self }`),
   and so does the 2.x type name (`@available(*, deprecated, message: "Use Streams.ReadCall; removed in 4.0.") public typealias Lazy = ReadCall`);
   both are removed in 4.0. `.buffered` is unchanged. `Failure` stays `any Error` only so that caller
   cancellation stays Swift's `CancellationError`; everything else the iterator throws is a `KurrentError`.
   The iterator also has `next(isolation:)`, so an iterator kept in actor state is advanced with
   `it.next(isolation: self)`; `next()` is `next(isolation: nil)`.
3. The RPC may still be open while the caller iterates. Anything that relied on "the RPC is over
   once `read()` returns" (none inside the SDK; pool borrowers possibly) must be reviewed.

   *Amended 2026-10-31 — reviewed in 3.0:* lazy reads use a second shared connection per endpoint
   (`ConnectionPurpose.read`), so a held read never makes unary calls, `.buffered` reads or gossip wait;
   about 100 reads in progress per connection, after which further reads wait for a stream slot.
   `KurrentDBClient.shutdown()` ends a read in progress, or one still opening, with
   `KurrentError.connectionClosed`. `KurrentDBPool` closes a borrowed client's connections when it is given
   back (`shutdownAwaitingHandlers()` before the lease is returned), so a `ReadCall` that leaked out of
   `withBorrowedClient` ends with `connectionClosed` instead of running against the next borrower's instance.
4. Error timing stays the same: a call the server rejects before accepting it surfaces at the first
   `next()` (and is retried per `OperationRetryPolicy`); errors after acceptance, including
   stream-not-found, surface during iteration. Caller cancellation throws `CancellationError`.

   *Amended 2026-10-31 — corrected:* the timing did not stay the same, and the sentence above was wrong
   about 2.x. In 2.x the buffered `read()` threw only node-discovery failures and `unsupportedFeature`;
   server rejections — stream-not-found, `resourceDeleted`, `accessDenied` — **and the selected node's
   connection failures** arrived inside the returned stream, during iteration. In 3.0 `read()` itself never
   throws, and all of them surface at the first `next()`: stream-not-found as `KurrentError.resourceNotFound`
   (the server's first message), the others as the `KurrentError` the unary calls use. Errors after the first
   element (a `CallOptions.timeout` expiring mid-stream, `shutdown()`, a transport failure) surface at the
   next element, also as `KurrentError`. Caller cancellation still throws `CancellationError`.

## Why not keep `read()` buffered forever

Event-sourced streams are unbounded by design. A read API whose memory grows with the stream is
the wrong default for the common case (rebuilding an aggregate, scanning `$all`); the 2026-10-04
audit flagged it (S02). Making the lazy form opt-in in 2.x and the default in 3.0 is the standard
deprecation cadence: one minor with both forms available, a deprecation warning in the last 2.x
minor, the switch in the major.

*Amended 2026-10-31 — the deprecation step was skipped (owner, 2026-10-28, U1):* 3.0 is the release after
2.6 and 2.7 is not released, so no 2.x release carries the deprecation warning on the buffered overload.
2.x callers meet the change in 3.0 directly: the forms the compiler still accepts change silently or with
`try` / `await` warnings, and the migration article lists them.

## Silent changes recorded in 3.0 (amended 2026-10-31)

Of the 3.0 design's complete list of silent changes (spec §2, S1–S17), three are about this decision's
semantics and are recorded here:

- **S2 — `defaultDeadline`.** 2.x: it bounded each attempt of the buffered RPC, from after node selection to
  the end of the drain. 3.0: it bounds **establishing** a lazy read as one budget, from node selection to the
  server's first response, waiting for a stream slot on the read connection included; its expiry is
  `KurrentError.deadlineExceeded` and is not retried. The iteration is not bounded by it. A caller-set
  `CallOptions.timeout` keeps gRPC semantics and spans the iteration. `.buffered` keeps the 2.x per-attempt
  bound, so a retried `.buffered` read can take up to `maxAttempts` × the deadline plus backoff.
- **S5 — a result iterated twice.** 2.x: the stored stream was a snapshot; a second loop yielded nothing.
  3.0: each iteration of a `ReadCall` opens its own RPC and replays from the start, including events
  appended in between. `.buffered` is the snapshot.
- **S6 — retries.** 2.x: the selected node's failures arrived inside the stream and were never retried; only
  discovery failures and `unsupportedFeature` were thrown from `read()`. (A `.buffered` read whose deadline
  expires mid-drain *is* retried, then and now: `deadlineExceeded` is a node failure; that is accepted 2.x
  behaviour `.buffered` keeps.) 3.0: before the server accepts a lazy read, failures the client classifies
  as node failures (not-leader, connection refused, `grpcError`, `grpcRuntimeError`) are retried per
  `OperationRetryPolicy` at the first `next()`, resetting the cached node. **Except** a pre-acceptance
  `deadlineExceeded` — the establishment budget's, or a caller's `CallOptions.timeout` expiring before
  acceptance, e.g. while waiting for a stream slot — which is final: no retry, no node reset (`withRetry`'s
  `isRetryable` predicate excludes it for the lazy open only).

## Why `ReadCall` is not an `AsyncSequence` in 2.x

Two `read(configure:)` overloads that differ only by return type are ambiguous at every call site
that does not spell the type (`for try await r in read()`, `let s = read()`, `read().reduce`).
A compile probe (Swift 6.4) showed that the ambiguity disappears only when the new overload is
synchronous, non-throwing and returns a type that is **not** an `AsyncSequence`: existing calls
(always written `try await read()`) resolve to the old overload, and `.lazy` / `.buffered` chains
resolve to `ReadCall`. Both conditions are hard requirements for the 2.x line.

*Amended 2026-10-31:* the "Known 2.x limitation" paragraphs that followed here (`let call = stream.read()`
needing a type annotation, and `stream.read` function references binding by context) described the
two-overload shape only. 3.0 removes the buffered overloads, so `read(configure:)` has one overload on
each target and both limitations are gone; the paragraphs were deleted (see this file's history for the
2.x text).

## Migration guide — to be written before 3.0

A "Migrating from 2.x to 3.0" DocC article must cover:

- `read()` is lazy: what changes for `for try await`, `reduce`, `first` users (nothing in syntax;
  memory and connection lifetime change).
- When to add `.buffered` (small reads kept in a variable and iterated later; code that must not
  hold an RPC open while it works on the result).
- `try await stream.read()` → `stream.read()` (the `try await` on a now-synchronous `read()` is
  a warning, not an error; remove it).
- The "stored iterator keeps the RPC open" edge and the recommendation to iterate directly.
- Subscription backpressure (already in 2.x on the `feat/read-call-lazy-buffered` branch; mention for completeness).
- The last 2.x minor should mark the old overload `@available(*, deprecated, message:)` pointing
  at this article. *Amended 2026-10-31: skipped (U1); no 2.x release carries this warning, see
  "Why not keep `read()` buffered forever".*

## 3.0 amendment: the hand-off (2026-10-31)

**The price 2.x paid.** grpc-swift 2 exposes a response stream only inside the handler closure of
`call(...)` and closes it when the closure returns. The 2.x `ReadCall.Lazy` iterator escapes that closure,
so the RPC ran in its own task and forwarded every message to the consumer through `ResponseHandoff`: one
task hand-off per element. That was the price of the escaping-iterator shape, measured in #191's live
setup at 17–19 µs per event against 11 µs for `.buffered` off an actor (≈ 1.6×), and 33–35 against
19–20 µs from the `MainActor`, where the consumer also paid an executor hop per element. 3.0's
`ReadCall: AsyncSequence` has the same escaping iterator, so without a change it would make that price the
default.

**What removes it: the parked handler.** `StreamingClientResponse.messages` (an `RPCAsyncSequence`) is
`Sendable`, so the handler does not have to forward elements: it hands the sequence out, opens the
acceptance gate and **parks** on a latch until the consumer is done (`ParkedCall` / `openParked`). The
consumer's own task iterates grpc-swift's sequence directly; nothing outlives the closure, because the
closure does not return until the iteration has ended. The handler records the RPC's terminal error
(deadline, shutdown, transport) in a first-write-wins slot that the iterator checks after every message,
so a cut-off read ends at the next element instead of draining what was already buffered.

**Two paths behind one iterator.** `Streams.ReadCall.Iterator.next(isolation:)` chooses on its first call
and keeps the choice. With no isolation (a plain async function, a detached task) it takes the **direct
path**: the parked handler, no `ResponseHandoff`. On an actor it takes the **hand-off path**: the RPC's task
forwards through `ResponseHandoff`, with the isolation threaded through `ResponseHandoff.next(isolation:)`
so the consumer hops once per element. The direct path loses on an actor because NIO's iterator under
grpc-swift's sequence has only `next()`, so the hop would happen inside the transport per element and the
protobuf decode would run on the actor. `for try await` passes `#isolation`, so the choice needs nothing
from the user, and either path is correct from any context; only the cost differs. Both paths share the
lease, the acceptance gate, `withRetry` with its `isRetryable` predicate, the read connection and the
establishment budget. `ResponseHandoff` stays for the actor path until NIO's iterator can take an isolation.

**Measurements.** The spike (`spike/parked-read`, 2026-10-28, #191's setup: release build, KurrentDB 26.2
single insecure node in Docker, amd64 emulated on arm64; a 1,000-event stream of ~300 B JSON events read
100 times per cell, each event decoded with `JSONDecoder`; CPU from `getrusage`; variants alternated, 3
rounds; medians, µs per event, CPU):

| Iterating from | `.buffered` | hand-off, `next()` only (2.6) | hand-off with `next(isolation:)` | **direct (parked)** |
|---|---|---|---|---|
| off any actor (`Task.detached`) | 13.0 | 20.5 | 21.1 | **12.5** (0.96× buffered) |
| the `MainActor` | 26.5 | 40.0 | **29.4** (1.11× buffered) | 40.6 (1.53×) |

The 3.0 implementation, measured in its review on 2026-10-30 with `OfflineBenchmarks` on macOS (a real
`KurrentDBClient` against the in-process fake server: no sockets, no HTTP/2 framing, no server work;
1,000 events of 100 B, p50 wall clock): `Client/read-lazy/1000x100B` (direct path) 3.85–3.94 ms against
`Client/read-buffered/1000x100B` 4.46–4.48 ms, about 0.87×; `Client/read-lazy-actor/1000x100B` (hand-off
path) 12 ms against a `.buffered` loop run from the same `@MainActor` helper (a scratch series, not a
committed benchmark) 14 ms, about 0.86×. So in 3.0 `read()` costs about what `.buffered` costs per event
off an actor, and at most ≈ 1.1× on one; `.buffered` is for snapshots, results iterated later and reads that
the deadline should bound as a whole, not for speed.

**Memory bound, updated.** On the direct path there is no element in hand-off: memory per read is bounded
by the transport's inbound message queue (10 messages by default) and one HTTP/2 stream flow-control window
(about 8 MiB by default). On the hand-off path add the one element held by the suspended producer, as the
Decision states.

## Alternatives considered

- Keep `AsyncThrowingStream` as the return type and make it lazy internally (`unfolding` + a
  cancel-on-release sentinel). Source-compatible, but the stream value itself owns the RPC, so a
  stream stored and never iterated holds the lease; and there is no natural home for an explicit
  `.buffered`.
- A closure-scoped form only (`read { events in … }`, `withEvents`): guarantees the RPC is closed
  before the call returns, but forces an extra nesting level on every read and departs from how
  Swift consumes async data (`URLSession.bytes`, `AsyncStream`). Rejected as the sole form;
  `read().lazy.reduce` covers the same need with the release happening in the iterator's `deinit`.
  *Amended 2026-10-31:* reconsidered in 3.0 (#191) as a way to avoid the per-element hand-off, and
  not needed: see the 3.0 amendment; the parked handler gives the direct path that performance under the
  `AsyncSequence` shape. (The 3.0 spelling of that example is `read().reduce`.)
- A marker axis (`delivery(.scoped)`, `read(.lazy)`, `read(loading: .lazy)`): naming never became
  self-explanatory and the option itself was unnecessary once both modes live on `ReadCall`.
