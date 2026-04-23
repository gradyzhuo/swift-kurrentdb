# API Documentation Update — Design Spec
**Date:** 2026-04-23  
**Scope:** All `public` symbols in `Sources/KurrentDB/` and `Sources/GRPCEncapsulates/`

---

## Goal

Rewrite all public API doc comments to be accurate, consistent, and concise. Many existing descriptions reflect an older API shape and need to be corrected. All symbols — even previously undocumented ones — receive coverage.

---

## Documentation Style

```swift
/// One-line summary sentence ending with a period.
///
/// Optional second paragraph only if the summary alone is ambiguous — 1–2 sentences max.
///
/// ```swift
/// // Code example for factory methods, builder patterns, and non-obvious usage only
/// ```
///
/// - Parameters:
///   - name: Description.
/// - Returns: Description.
/// - Throws: `KurrentError` cases that can be raised.
```

### Rules

- Start directly with noun or verb — no "This is a..." or "A type that..." filler
- **Target types and namespace types**: one-line summary only, no parameter/return sections
- **Enum cases**: inline one-liner `/// Description.`
- **Properties**: one-line `/// Description.`
- **Code examples**: add for factory methods, builder patterns, and non-obvious usage; omit for simple properties and enum cases
- No changes outside doc comments — logic, signatures, and access control are untouched
- `EventData` is still supported and public; do not add `@available(*, deprecated)`

---

## Execution Strategy

Nine parallel subagents, each responsible for one module boundary:

| Subagent | Scope |
|---|---|
| 1. Core/Config | `ClientSettings`, `Endpoint`, `Authentication`, `KeepAlive`, `NodePreference`, `TopologyClusterMode`, `OperationRetryPolicy` |
| 2. Core/Types | `Direction`, `TimeSpan`, `UUIDOption`, `StreamIdentifier`, `StreamPosition`, `StreamRevision`, `StreamMetadata`, `StreamSelector`, `SubscriptionFilter`, `PositionCursor`, `RevisionCursor`, `ContentType` |
| 3. Core/Events | `EventData`, `EventRecord`, `RecordedEvent`, `ReadEvent`, `StreamEvent` |
| 4. Core/Error + Client | `KurrentError`, `KurrentDBClient`, `KurrentDBClientProtocol` |
| 5. Streams | `Streams<Target>`, `ReadResponse`, `Subscription`, all stream target types |
| 6. Projections | `Projections<Target>`, `Projection` namespace, all projection target types |
| 7. PersistentSubscriptions | `PersistentSubscriptions<Target>`, all subscription target types |
| 8. Users + Operations + Monitoring | `Users<Target>`, `UserDetails`, `UserGroup`, `Operations<Target>`, `Monitoring`, target types |
| 9. Gossip + NodeSelector | `Gossip`, `MemberInfo`, `VNodeState`, `NodeSelector`, `NodeDiscover` |

---

## Completion Criteria

Each subagent is done when:

1. Every `public` symbol has a doc comment
2. Style rules applied consistently throughout
3. No factually incorrect statements — descriptions match actual current behaviour
4. Existing correct content rewritten to concise style (no legacy prose left behind)
5. No changes outside doc comments

After all subagents complete: `swift build` must pass.
