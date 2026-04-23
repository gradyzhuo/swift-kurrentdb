# API Documentation Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite all `public` API doc comments in `Sources/KurrentDB/` to be accurate, concise, and consistently styled.

**Architecture:** Nine independent tasks, one per module boundary, executed in parallel. Each task reads its files, rewrites only doc comments (no logic/signature changes), and writes back. A final build verification task runs after all nine complete.

**Tech Stack:** Swift 6, `swift build` for verification, no test changes required.

---

## Documentation Style Reference

Apply this style to every public symbol:

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

**Rules (non-negotiable):**
- Start with noun or verb — never "This is a..." or "A type that..."
- **Target types and namespace types**: one-line summary only, no parameter/return sections
- **Enum cases**: inline one-liner `/// Description.`
- **Properties**: one-line `/// Description.`
- **Code examples**: add for factory methods, builder patterns, non-obvious usage; omit for simple properties/cases
- `EventData` is still supported — do NOT add `@available(*, deprecated)`
- Touch ONLY doc comments — no logic, signature, or access-control changes

---

## Task 1: Core/Config

**Files to modify:**
- `Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift`
- `Sources/KurrentDB/Core/ClientSettings/Endpoint.swift`
- `Sources/KurrentDB/Core/ClientSettings/Authentication.swift`
- `Sources/KurrentDB/Core/ClientSettings/KeepAlive.swift`
- `Sources/KurrentDB/Core/ClientSettings/NodePreference.swift`
- `Sources/KurrentDB/Core/ClientSettings/TopologyClusterMode.swift`
- `Sources/KurrentDB/Core/RetryPolicy.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full to understand every public symbol's current doc comment and actual behavior.

- [ ] **Step 2: Rewrite doc comments — ClientSettings.swift**

Cover: type summary, all `public` properties (one-liners), all `public` init/factory methods (`localhost()`, `remote()`, `parse(connectionString:)`, `parseCertificate(path:)`) with parameters/returns/throws, all builder methods with parameter docs. Add a code example on `localhost()` and `parse(connectionString:)`. Remove any prose that no longer matches current fields.

- [ ] **Step 3: Rewrite doc comments — Endpoint.swift**

Cover: type summary, `host`/`port`/`isLocalhost` properties, all inits, `target` property. Add a code example showing string literal usage.

- [ ] **Step 4: Rewrite doc comments — Authentication.swift**

Cover: enum summary, both cases (`credentials`, `x509`) with inline one-liners.

- [ ] **Step 5: Rewrite doc comments — KeepAlive.swift**

Cover: struct summary, `default` static, both inits with parameter docs.

- [ ] **Step 6: Rewrite doc comments — NodePreference.swift**

Cover: enum summary, all four cases (`leader`, `follower`, `random`, `readOnlyReplica`) with inline one-liners.

- [ ] **Step 7: Rewrite doc comments — TopologyClusterMode.swift**

Cover: enum summary, all three cases (`standalone`, `dns`, `seeds`) with inline one-liners.

- [ ] **Step 8: Rewrite doc comments — RetryPolicy.swift**

Cover: struct summary, all properties (one-liners), `JitterStrategy` enum and its cases, `default` static, init with parameter docs.

- [ ] **Step 9: Commit**

```bash
git add Sources/KurrentDB/Core/ClientSettings/ClientSettings.swift \
        Sources/KurrentDB/Core/ClientSettings/Endpoint.swift \
        Sources/KurrentDB/Core/ClientSettings/Authentication.swift \
        Sources/KurrentDB/Core/ClientSettings/KeepAlive.swift \
        Sources/KurrentDB/Core/ClientSettings/NodePreference.swift \
        Sources/KurrentDB/Core/ClientSettings/TopologyClusterMode.swift \
        Sources/KurrentDB/Core/RetryPolicy.swift
git commit -m "[DOCS] Update doc comments for Core/Config types"
```

---

## Task 2: Core/Types

**Files to modify:**
- `Sources/KurrentDB/Core/Direction.swift`
- `Sources/KurrentDB/Core/TimeSpan.swift`
- `Sources/KurrentDB/Core/UUIDOption.swift`
- `Sources/KurrentDB/Core/Stream/StreamIdentifier.swift`
- `Sources/KurrentDB/Core/Stream/StreamPosition.swift`
- `Sources/KurrentDB/Core/Stream/StreamRevisionRule.swift`
- `Sources/KurrentDB/Core/Stream/StreamMetadata.swift`
- `Sources/KurrentDB/Core/Stream/StreamSelector.swift`
- `Sources/KurrentDB/Core/SubscriptionFilter.swift`
- `Sources/KurrentDB/Core/Cursor/PositionCursor.swift`
- `Sources/KurrentDB/Core/Cursor/RevisionCursor.swift`
- `Sources/KurrentDB/Core/Event/ContentType.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — Direction.swift, TimeSpan.swift, UUIDOption.swift, ContentType.swift**

Each is a small enum. Cover: enum summary, all cases with inline one-liners.

- [ ] **Step 3: Rewrite doc comments — StreamIdentifier.swift**

Cover: struct summary, `name`/`encoding`/`category` properties, `all` static, both inits, `ExpressibleByStringLiteral` conformance note. Add a code example showing string literal init.

- [ ] **Step 4: Rewrite doc comments — StreamPosition.swift**

Cover: struct summary, `commit`/`prepare` properties, `at(commitPosition:preparePosition:)` factory method.

- [ ] **Step 5: Rewrite doc comments — StreamRevisionRule.swift**

Cover: `StreamRevision` enum summary, all cases (`any`, `noStream`, `streamExists`, `at(_:)`) with inline one-liners.

- [ ] **Step 6: Rewrite doc comments — StreamMetadata.swift**

Cover: struct summary, all properties (one-liners), `Acl` enum and cases, `StreamAcl` struct and its properties, all builder methods with parameter docs.

- [ ] **Step 7: Rewrite doc comments — StreamSelector.swift**

Cover: enum summary, both cases (`all`, `specified`) with inline one-liners.

- [ ] **Step 8: Rewrite doc comments — SubscriptionFilter.swift**

Cover: struct summary, `Window` enum and cases, `FilterType` enum and cases, all properties, all builder methods, all static factory methods with parameter docs. Add a code example for `onStreamName(prefix:)` and `onEventType(regex:)`.

- [ ] **Step 9: Rewrite doc comments — PositionCursor.swift, RevisionCursor.swift**

Cover each: enum summary, all cases with inline one-liners, static factory helpers with return docs.

- [ ] **Step 10: Commit**

```bash
git add Sources/KurrentDB/Core/Direction.swift \
        Sources/KurrentDB/Core/TimeSpan.swift \
        Sources/KurrentDB/Core/UUIDOption.swift \
        Sources/KurrentDB/Core/Stream/StreamIdentifier.swift \
        Sources/KurrentDB/Core/Stream/StreamPosition.swift \
        Sources/KurrentDB/Core/Stream/StreamRevisionRule.swift \
        Sources/KurrentDB/Core/Stream/StreamMetadata.swift \
        Sources/KurrentDB/Core/Stream/StreamSelector.swift \
        Sources/KurrentDB/Core/SubscriptionFilter.swift \
        Sources/KurrentDB/Core/Cursor/PositionCursor.swift \
        Sources/KurrentDB/Core/Cursor/RevisionCursor.swift \
        Sources/KurrentDB/Core/Event/ContentType.swift
git commit -m "[DOCS] Update doc comments for Core/Types"
```

---

## Task 3: Core/Events

**Files to modify:**
- `Sources/KurrentDB/Core/Event/EventData.swift`
- `Sources/KurrentDB/Core/Event/EventRecord.swift`
- `Sources/KurrentDB/Core/Event/RecordedEvent.swift`
- `Sources/KurrentDB/Core/Event/ReadEvent.swift`
- `Sources/KurrentDB/Core/Event/StreamEvent.swift`
- `Sources/KurrentDB/Core/Event/EventStoreEvent.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — EventStoreEvent.swift**

Cover: protocol summary, all associated requirements.

- [ ] **Step 3: Rewrite doc comments — EventData.swift**

Cover: struct summary (do NOT add `@available(*, deprecated)` — it is still supported), `Payload` enum and cases, all properties, all `init` overloads with parameter docs. Add a code example for the primary init.

- [ ] **Step 4: Rewrite doc comments — EventRecord.swift**

Cover: struct summary, `Payload` enum and cases, `Schema` struct and its properties, `Schema.Format` enum and all cases, all properties, all inits with parameter/throws docs, all builder methods. Add a code example for creating a JSON record.

- [ ] **Step 5: Rewrite doc comments — RecordedEvent.swift**

Cover: struct summary, all properties (one-liners), `decode(to:)` method with parameter/returns/throws docs.

- [ ] **Step 6: Rewrite doc comments — ReadEvent.swift**

Cover: struct summary, all properties (one-liners), `noPosition` computed property.

- [ ] **Step 7: Rewrite doc comments — StreamEvent.swift**

Cover: struct summary, all properties, all inits with parameter docs. Add a code example showing construction.

- [ ] **Step 8: Commit**

```bash
git add Sources/KurrentDB/Core/Event/EventData.swift \
        Sources/KurrentDB/Core/Event/EventRecord.swift \
        Sources/KurrentDB/Core/Event/RecordedEvent.swift \
        Sources/KurrentDB/Core/Event/ReadEvent.swift \
        Sources/KurrentDB/Core/Event/StreamEvent.swift \
        Sources/KurrentDB/Core/Event/EventStoreEvent.swift
git commit -m "[DOCS] Update doc comments for Core/Events"
```

---

## Task 4: Core/Error + Client

**Files to modify:**
- `Sources/KurrentDB/Core/Error/KurrentError.swift`
- `Sources/KurrentDB/Core/Error/KurrentError+RevisionOption.swift`
- `Sources/KurrentDB/Core/Error/KurrentError+WrongExpectedVersion.swift`
- `Sources/KurrentDB/KurrentDBClient.swift`
- `Sources/KurrentDB/KurrentDBClientProtocol.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — KurrentError.swift**

Cover: enum summary, every case with inline one-liners that accurately describe when each error is thrown. Verify each case description matches actual server/client behavior.

- [ ] **Step 3: Rewrite doc comments — KurrentError+RevisionOption.swift and KurrentError+WrongExpectedVersion.swift**

Cover any public nested types (`ExpectedRevisionOption`, `CurrentRevisionOption`) — enum summaries, all cases with inline one-liners.

- [ ] **Step 4: Rewrite doc comments — KurrentDBClient.swift**

Cover: class summary, all `public` properties (one-liners), `init(settings:numberOfThreads:defaultCallOptions:)` with parameter docs, `shutdown()` with throws doc. Add a code example showing basic client setup.

- [ ] **Step 5: Rewrite doc comments — KurrentDBClientProtocol.swift**

Cover: protocol summary, all factory methods (`streams(of:)`, `streams(specified:)`, `persistentSubscriptions(of:)`, etc.) with parameter/returns docs, all computed properties (`allStreams`, `multiStreams`, `allPersistentSubscriptions`, `users`, `monitoring`) with one-liners. Add a code example showing how factory methods are used.

- [ ] **Step 6: Commit**

```bash
git add Sources/KurrentDB/Core/Error/KurrentError.swift \
        Sources/KurrentDB/Core/Error/KurrentError+RevisionOption.swift \
        Sources/KurrentDB/Core/Error/KurrentError+WrongExpectedVersion.swift \
        Sources/KurrentDB/KurrentDBClient.swift \
        Sources/KurrentDB/KurrentDBClientProtocol.swift
git commit -m "[DOCS] Update doc comments for KurrentError and client entry points"
```

---

## Task 5: Streams

**Files to modify:**
- `Sources/KurrentDB/Streams/Streams.swift`
- `Sources/KurrentDB/Streams/Streams.ReadResponse.swift`
- `Sources/KurrentDB/Streams/Streams.Subscription.swift`
- `Sources/KurrentDB/Streams/Target/StreamsTarget.swift`
- `Sources/KurrentDB/Streams/Target/SpecifiedStreamTarget.swift`
- `Sources/KurrentDB/Streams/Target/SpecifiedStream.swift`
- `Sources/KurrentDB/Streams/Target/ProjectionStream.swift`
- `Sources/KurrentDB/Streams/Target/AllStreamsTarget.swift`
- `Sources/KurrentDB/Streams/Target/MultiStreamsTarget.swift`
- `Sources/KurrentDB/Streams/Target/AnyStreamTarget.swift`
- `Sources/KurrentDB/Streams/API/Streams+AllStreamsTarget.swift`
- `Sources/KurrentDB/Streams/API/Streams+SpecifiedStreamTarget.swift`
- `Sources/KurrentDB/Streams/API/Streams+ProjectionStream.swift`
- `Sources/KurrentDB/Streams/KurrentDBClient+Streams.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — target types**

For `StreamsTarget`, `SpecifiedStreamTarget`: protocol summaries only (one-liners).
For `SpecifiedStream`, `ProjectionStream`, `AllStreamsTarget`, `MultiStreamsTarget`, `AnyStreamTarget`: struct/class one-line summaries only.

- [ ] **Step 3: Rewrite doc comments — Streams.swift**

Cover: class summary, `target` property. Add a code example showing how `Streams` is obtained via the client.

- [ ] **Step 4: Rewrite doc comments — Streams.ReadResponse.swift**

Cover: enum summary, both cases with inline one-liners, `event` computed property with returns/throws docs.

- [ ] **Step 5: Rewrite doc comments — Streams.Subscription.swift**

Cover: struct summary, `events` property, `subscriptionId` property, `cancel()` method.

- [ ] **Step 6: Rewrite doc comments — API extension files**

For `Streams+SpecifiedStreamTarget.swift`: cover `append`, `read`, `subscribe`, `delete`, `tombstone`, `setMetadata`, `getMetadata` methods — each with parameter/returns/throws docs. Add code examples for `append` and `read`.
For `Streams+AllStreamsTarget.swift`: cover `read`, `subscribe` methods with parameter/returns/throws docs.
For `Streams+ProjectionStream.swift`: cover its public methods with parameter/returns/throws docs.

- [ ] **Step 7: Rewrite doc comments — KurrentDBClient+Streams.swift**

Cover all `streams(of:)` / `streams(specified:)` factory methods with parameter/returns docs.

- [ ] **Step 8: Commit**

```bash
git add Sources/KurrentDB/Streams/Streams.swift \
        Sources/KurrentDB/Streams/Streams.ReadResponse.swift \
        Sources/KurrentDB/Streams/Streams.Subscription.swift \
        Sources/KurrentDB/Streams/Target/ \
        Sources/KurrentDB/Streams/API/ \
        Sources/KurrentDB/Streams/KurrentDBClient+Streams.swift
git commit -m "[DOCS] Update doc comments for Streams module"
```

---

## Task 6: Projections

**Files to modify:**
- `Sources/KurrentDB/Core/Projection/Projection.swift`
- `Sources/KurrentDB/Core/Projection/Projection.Detail.swift`
- `Sources/KurrentDB/Core/Projection/Projection.Mode.swift`
- `Sources/KurrentDB/Core/Projection/Projection.Status.swift`
- `Sources/KurrentDB/Projections/Projections.swift`
- `Sources/KurrentDB/Projections/Target/ProjectionsTarget.swift`
- `Sources/KurrentDB/Projections/Target/ProjectionControlable.swift`
- `Sources/KurrentDB/Projections/Target/NameTarget.swift`
- `Sources/KurrentDB/Projections/Target/SpecifiedContinuousProjectionTarget.swift`
- `Sources/KurrentDB/Projections/Target/SpecifiedTransientProjectionTarget.swift`
- `Sources/KurrentDB/Projections/Target/UnspecifiedContinuousProjectionTarget.swift`
- `Sources/KurrentDB/Projections/Target/UnspecifiedTransientProjectionTarget.swift`
- `Sources/KurrentDB/Projections/Target/OneTimeProjectionTarget.swift`
- `Sources/KurrentDB/Projections/Target/AnyProjectionsTarget.swift`
- `Sources/KurrentDB/Projections/API/Projections+AnyMode.swift`
- `Sources/KurrentDB/Projections/API/Projections+ContinuousMode.swift`
- `Sources/KurrentDB/Projections/API/Projections+OneTimeMode.swift`
- `Sources/KurrentDB/Projections/API/Projections+TransientMode.swift`
- `Sources/KurrentDB/Projections/KurrentDBClient+Projections.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — Projection namespace types**

`Projection.swift`: namespace summary. `Projection.Detail`: struct summary + all public properties as one-liners. `Projection.Mode`: enum summary + all cases with inline one-liners. `Projection.Status`: enum summary + all cases with inline one-liners.

- [ ] **Step 3: Rewrite doc comments — target types**

`ProjectionsTarget`, `ProjectionControlable`: protocol one-line summaries.
All concrete target structs (`NameTarget`, `SpecifiedContinuousProjectionTarget`, etc.): one-line summaries only.

- [ ] **Step 4: Rewrite doc comments — Projections.swift**

Cover: class summary, `target` property. Add a code example showing how `Projections` is obtained via the client.

- [ ] **Step 5: Rewrite doc comments — API extension files**

For each of `Projections+ContinuousMode.swift`, `Projections+TransientMode.swift`, `Projections+OneTimeMode.swift`, `Projections+AnyMode.swift`: cover all public methods (`enable`, `disable`, `abort`, `reset`, `delete`, `update`, `detail`, `result`, `state`, `create`) with parameter/returns/throws docs. Add a code example for `create` in the continuous mode file.

- [ ] **Step 6: Rewrite doc comments — KurrentDBClient+Projections.swift**

Cover all factory methods with parameter/returns docs.

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Core/Projection/ \
        Sources/KurrentDB/Projections/Projections.swift \
        Sources/KurrentDB/Projections/Target/ \
        Sources/KurrentDB/Projections/API/ \
        Sources/KurrentDB/Projections/KurrentDBClient+Projections.swift
git commit -m "[DOCS] Update doc comments for Projections module"
```

---

## Task 7: PersistentSubscriptions

**Files to modify:**
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.Settings.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.SystemConsumerStrategy.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.StreamSelection.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistenSubscription.EventResult.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.ConnectionInfo.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.Measurement.swift`
- `Sources/KurrentDB/Core/PersistenSubscription/PersistentSubscription.SubscriptionInfo.swift`
- `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.swift`
- `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.ReadResponse.swift`
- `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.Subscription.swift`
- `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.StreamSelection.swift`
- `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptionStreamSelection.swift`
- `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptionsSettingsBuildable.swift`
- `Sources/KurrentDB/PersistentSubscriptions/Target/PersistentSubscriptionTarget.swift`
- `Sources/KurrentDB/PersistentSubscriptions/Target/SpecifiedPersistentSubscriptionTarget.swift`
- `Sources/KurrentDB/PersistentSubscriptions/Target/AllStreamPersistentSubscriptionTarget.swift`
- `Sources/KurrentDB/PersistentSubscriptions/Target/AllPersistentSubscriptionTarget.swift`
- `Sources/KurrentDB/PersistentSubscriptions/Target/FilterStreamPersistentSubscriptionTarget.swift`
- `Sources/KurrentDB/PersistentSubscriptions/Target/AnyPersistentSubscriptionTarget.swift`
- `Sources/KurrentDB/PersistentSubscriptions/API/PersistentSubscriptions+All.swift`
- `Sources/KurrentDB/PersistentSubscriptions/API/PersistentSubscriptions+AllStream.swift`
- `Sources/KurrentDB/PersistentSubscriptions/API/PersistentSubscriptions+FilterStream.swift`
- `Sources/KurrentDB/PersistentSubscriptions/API/PersistentSubscriptions+Specified.swift`
- `Sources/KurrentDB/PersistentSubscriptions/KurrentDBClient+PersistentSubscriptions.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — Core PersistentSubscription types**

`PersistentSubscription.swift`: namespace summary.
`PersistentSubscription.Settings`: struct summary + all public properties as one-liners + builder methods with parameter docs.
`PersistentSubscription.SystemConsumerStrategy`: enum summary + all cases with inline one-liners.
`PersistentSubscription.StreamSelection`, `EventResult`, `ConnectionInfo`, `Measurement`, `SubscriptionInfo`: each type summary + all public properties as one-liners.

- [ ] **Step 3: Rewrite doc comments — target types**

`PersistentSubscriptionTarget` protocol: one-line summary.
All concrete targets (`SpecifiedPersistentSubscriptionTarget`, `AllStreamPersistentSubscriptionTarget`, etc.): one-line summaries only.
`PersistentSubscriptionStreamSelection` protocol and conforming types: one-line summaries.

- [ ] **Step 4: Rewrite doc comments — PersistentSubscriptions.swift, ReadResponse, Subscription, StreamSelection**

`PersistentSubscriptions.swift`: class summary, `target` property.
`ReadResponse`: enum summary, all cases with inline one-liners, computed property with returns/throws.
`Subscription`: struct summary, all properties, `cancel()` / `ack()` / `nack()` methods with parameter/throws docs.
`StreamSelection`: type summary + properties.
`PersistentSubscriptionsSettingsBuildable`: protocol summary.

- [ ] **Step 5: Rewrite doc comments — API extension files**

For each of `PersistentSubscriptions+Specified.swift`, `PersistentSubscriptions+AllStream.swift`, `PersistentSubscriptions+FilterStream.swift`, `PersistentSubscriptions+All.swift`: cover all public methods (`create`, `update`, `delete`, `subscribe`, `getInfo`, `list`, `replayParked`) with parameter/returns/throws docs. Add a code example for `subscribe` in the Specified file.

- [ ] **Step 6: Rewrite doc comments — KurrentDBClient+PersistentSubscriptions.swift**

Cover all factory methods with parameter/returns docs.

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Core/PersistenSubscription/ \
        Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.swift \
        Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.ReadResponse.swift \
        Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.Subscription.swift \
        Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.StreamSelection.swift \
        Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptionStreamSelection.swift \
        Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptionsSettingsBuildable.swift \
        Sources/KurrentDB/PersistentSubscriptions/Target/ \
        Sources/KurrentDB/PersistentSubscriptions/API/ \
        Sources/KurrentDB/PersistentSubscriptions/KurrentDBClient+PersistentSubscriptions.swift
git commit -m "[DOCS] Update doc comments for PersistentSubscriptions module"
```

---

## Task 8: Users + Operations + Monitoring

**Files to modify:**
- `Sources/KurrentDB/Users/Users.swift`
- `Sources/KurrentDB/Users/UserDetails.swift`
- `Sources/KurrentDB/Users/UserGroup.swift`
- `Sources/KurrentDB/Users/Target/UsersTarget.swift`
- `Sources/KurrentDB/Users/Target/UserCreatable.swift`
- `Sources/KurrentDB/Users/Target/UserControllable.swift`
- `Sources/KurrentDB/Users/Target/AllUsersTarget.swift`
- `Sources/KurrentDB/Users/Target/SpecifiedUserTarget.swift`
- `Sources/KurrentDB/Users/KurrentDBClient+Users.swift`
- `Sources/KurrentDB/Operations/Operations.swift`
- `Sources/KurrentDB/Operations/OperationsTarget.swift`
- `Sources/KurrentDB/Operations/ScavengeResponse.swift`
- `Sources/KurrentDB/Operations/Protocols/NodeControllable.swift`
- `Sources/KurrentDB/Operations/Protocols/ScavengeControllable.swift`
- `Sources/KurrentDB/Operations/Protocols/ScavengeCreatable.swift`
- `Sources/KurrentDB/Operations/Protocols/SystemControllable.swift`
- `Sources/KurrentDB/Operations/Targets/ActiveScavenge.swift`
- `Sources/KurrentDB/Operations/Targets/NodeOperations.swift`
- `Sources/KurrentDB/Operations/Targets/ScavengeOperations.swift`
- `Sources/KurrentDB/Operations/Targets/SystemOperations.swift`
- `Sources/KurrentDB/Operations/KurrentDBClient+ServerOperations.swift`
- `Sources/KurrentDB/Monitoring/Monitoring.swift`
- `Sources/KurrentDB/Monitoring/KurrentDBClient+Monitoring.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — Users types**

`UsersTarget`, `UserCreatable`, `UserControllable` protocols: one-line summaries.
`AllUsersTarget`, `SpecifiedUserTarget` structs: one-line summaries.
`UserDetails`: struct summary + all properties as one-liners + init parameter docs.
`UserGroup`: enum summary + all cases with inline one-liners + `rawValue` + `init(rawValue:)` docs. Add a code example showing string literal usage.
`Users.swift`: class summary + `target` property.
`KurrentDBClient+Users.swift`: factory method docs.
Extension methods (`create`, `details`, `enable`, `disable`, `update`, `changePassword`, `resetPassword`): full parameter/returns/throws docs.

- [ ] **Step 3: Rewrite doc comments — Operations types**

`OperationsTarget` protocol and all sub-protocols (`ScavengeCreatable`, `ScavengeControllable`, `NodeControllable`, `SystemControllable`): one-line summaries.
`ScavengeOperations`, `ActiveScavenge`, `NodeOperations`, `SystemOperations` targets: one-line summaries.
`Operations.swift`: class summary + `target` property.
`OperationsTarget.swift` file (if it has extension methods): parameter/returns/throws docs.
`ScavengeResponse`: struct/enum summary + all properties/cases.
`KurrentDBClient+ServerOperations.swift`: factory method docs.

- [ ] **Step 4: Rewrite doc comments — Monitoring**

`Monitoring.swift`: class summary, `stats(useMetadata:refreshTimePeriodInMs:)` method with parameter/returns/throws docs.
`KurrentDBClient+Monitoring.swift`: factory method docs.

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/Users/ \
        Sources/KurrentDB/Operations/ \
        Sources/KurrentDB/Monitoring/
git commit -m "[DOCS] Update doc comments for Users, Operations, and Monitoring modules"
```

---

## Task 9: Gossip + NodeSelector

**Files to modify:**
- `Sources/KurrentDB/Gossip/Gossip.swift`
- `Sources/KurrentDB/Gossip/MemberInfo.swift`
- `Sources/KurrentDB/Gossip/VNodeState.swift`
- `Sources/KurrentDB/Gossip/KurrentDBClient+Gossip.swift`
- `Sources/KurrentDB/Core/NodeSelector.swift`

- [ ] **Step 1: Read all files**

Read each file listed above in full.

- [ ] **Step 2: Rewrite doc comments — VNodeState.swift**

Enum summary + all 16 cases with accurate inline one-liners describing each node state in the Kurrent cluster lifecycle.

- [ ] **Step 3: Rewrite doc comments — MemberInfo.swift**

Struct summary + all public properties (`instanceId`, `timeStamp`, `state`, `isAlive`, `httpEndPoint`) as one-liners.

- [ ] **Step 4: Rewrite doc comments — Gossip.swift**

Class summary, `read(timeout:notAllowedStates:)` method with parameter/returns/throws docs.

- [ ] **Step 5: Rewrite doc comments — KurrentDBClient+Gossip.swift**

Cover the `gossip` factory property/method with returns docs.

- [ ] **Step 6: Rewrite doc comments — NodeSelector.swift**

`NodeSelector` actor summary, `select()` method with returns/throws docs.
`NodeDiscover` actor summary (one-liner — internal use), `next()` method docs.

- [ ] **Step 7: Commit**

```bash
git add Sources/KurrentDB/Gossip/ \
        Sources/KurrentDB/Core/NodeSelector.swift
git commit -m "[DOCS] Update doc comments for Gossip and NodeSelector"
```

---

## Task 10: Final Build Verification

**Depends on:** Tasks 1–9 all complete.

- [ ] **Step 1: Run swift build**

```bash
cd /Volumes/Development/swift-kurrentdb && swift build
```

Expected: build succeeds with no errors or warnings related to documentation.

- [ ] **Step 2: If build fails, fix compilation errors only**

Doc comment changes should never break the build. If errors appear, check that no signatures were accidentally modified. Fix only what is needed to restore a clean build.

- [ ] **Step 3: Commit fix if needed**

```bash
git add <affected files>
git commit -m "[DOCS] Fix build issues after documentation update"
```
