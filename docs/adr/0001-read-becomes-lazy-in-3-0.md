# ADR 0001 — `read()` delivers events lazily in 3.0

- Status: accepted (2026-10-06)
- Applies to: `Streams.read(configure:)` on specified streams and `$all`
- Related: `docs/superpowers/specs/2026-10-06-read-call-lazy-buffered-design.md`, security audit 2026-10-04 item S02 (PR #148 was the superseded first attempt)

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
3. The RPC may still be open while the caller iterates. Anything that relied on "the RPC is over
   once `read()` returns" (none inside the SDK; pool borrowers possibly) must be reviewed.
4. Error timing stays the same: a call the server rejects before accepting it surfaces at the first
   `next()` (and is retried per `OperationRetryPolicy`); errors after acceptance, including
   stream-not-found, surface during iteration. Caller cancellation throws `CancellationError`.

## Why not keep `read()` buffered forever

Event-sourced streams are unbounded by design. A read API whose memory grows with the stream is
the wrong default for the common case (rebuilding an aggregate, scanning `$all`); the 2026-10-04
audit flagged it (S02). Making the lazy form opt-in in 2.x and the default in 3.0 is the standard
deprecation cadence: one minor with both forms available, a deprecation warning in the last 2.x
minor, the switch in the major.

## Why `ReadCall` is not an `AsyncSequence` in 2.x

Two `read(configure:)` overloads that differ only by return type are ambiguous at every call site
that does not spell the type (`for try await r in read()`, `let s = read()`, `read().reduce`).
A compile probe (Swift 6.4) showed that the ambiguity disappears only when the new overload is
synchronous, non-throwing and returns a type that is **not** an `AsyncSequence`: existing calls
(always written `try await read()`) resolve to the old overload, and `.lazy` / `.buffered` chains
resolve to `ReadCall`. Both conditions are hard requirements for the 2.x line.

Known 2.x limitation: `let call = stream.read()` without `try await` and without `.lazy` /
`.buffered` resolves to the old overload and fails to compile; write `let call: Streams<SpecifiedStream>.ReadCall = …`.

An unannotated function reference `stream.read` formed in an async context keeps selecting the buffered
overload; one formed in a synchronous context selects the `ReadCall` overload, so spell the type if that
matters. `@_disfavoredOverload` does not change this (verified). This is the one accepted source change in
the 2.x line: storing `stream.read` as a function value in a synchronous context is rare, the failure is a
compile error rather than a silent change, and keeping the name `read` was judged worth more than a
separate factory name.

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
  at this article.

## Alternatives considered

- Keep `AsyncThrowingStream` as the return type and make it lazy internally (`unfolding` + a
  cancel-on-release sentinel). Source-compatible, but the stream value itself owns the RPC, so a
  stream stored and never iterated holds the lease; and there is no natural home for an explicit
  `.buffered`.
- A closure-scoped form only (`read { events in … }`, `withEvents`): guarantees the RPC is closed
  before the call returns, but forces an extra nesting level on every read and departs from how
  Swift consumes async data (`URLSession.bytes`, `AsyncStream`). Rejected as the sole form;
  `read().lazy.reduce` covers the same need with the release happening in the iterator's `deinit`.
- A marker axis (`delivery(.scoped)`, `read(.lazy)`, `read(loading: .lazy)`): naming never became
  self-explanatory and the option itself was unnecessary once both modes live on `ReadCall`.
