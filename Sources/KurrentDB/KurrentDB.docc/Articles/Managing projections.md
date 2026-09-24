# Managing projections

Create, control and query projections through ``KurrentDBClient``.

## Creating a client

Managing projections needs credentials with the right permissions:

```swift
let settings = ClientSettings.localhost()
    .authenticated(.credentials(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

## Choosing a target

Every operation starts from a ``Projections`` value for a target. The target decides which operations are available, so calling one that doesn't apply fails at compile time:

| Accessor | Operations |
|----------|------------|
| `client.projections(of: .continuous(name:))` | `create(query:configure:)`, plus every control operation |
| `client.projections(of: .transient(name:))` | `create(query:)`, plus every control operation |
| `client.projections(of: .onetime)` | `create(query:)`, `list()` |
| `client.projections(name:)` | `enable`, `disable`, `abort`, `reset`, `delete`, `update`, `detail`, `state`, `result` |
| `client.projections(system:)` | The same, for a system projection such as `.byCategory` |
| `client.projections(of: .anyMode)` | `list()`, `restartSubsystem()` |
| `client.projections(of: .anyContinuous)` / `.anyTransient` | `list()` for that mode |

## Create a projection

A continuous projection processes every event up to the end of the store, then keeps processing new events as they are appended. The query is the projection's JavaScript. Projections have names, which you use to enable, disable or query them.

```swift
let js = """
fromAll()
    .when({
        $init: function() {
            return {
                count: 0
            };
        },
        $any: function(s, e) {
            s.count += 1;
        }
    })
    .outputState();
"""
let name = "countEvents_Create_\(UUID())"

try await client.projections(of: .continuous(name: name)).create(query: js)
```

Set `emitEnabled` or `trackEmittedStreams` in the closure to control emitted streams:

<!-- snippet:continue -->
```swift
try await client.projections(of: .continuous(name: "emitting-\(UUID())")).create(query: js) {
    $0.emitEnabled = true
    $0.trackEmittedStreams = true
}
```

Creating a projection whose name is already taken throws ``KurrentError/resourceAlreadyExists``:

<!-- snippet:continue -->
```swift
do {
    try await client.projections(of: .continuous(name: name)).create(query: js)
} catch KurrentError.resourceAlreadyExists {
    print("\(name) already exists")
}
```

## Restart the subsystem

Restarts the whole projection subsystem. The user must be in the `$ops` or `$admins` group.

```swift
try await client.projections(of: .anyMode).restartSubsystem()
```

## Enable a projection

Enables an existing projection. An enabled projection processes events, and keeps doing so after the server or the projection subsystem restarts. You need access to the projection; see the [ACL documentation](https://docs.kurrent.io/server/v24.10/security/user-authorization.html).

```swift
try await client.projections(system: .byCategory).enable()
```

Enabling a projection that doesn't exist throws ``KurrentError/resourceNotFound(reason:)``:

```swift
do {
    try await client.projections(name: "projection that does not exist").enable()
} catch KurrentError.resourceNotFound(let reason) {
    print(reason)
}
```

The other control operations below throw the same error for a projection that doesn't exist.

## Disable a projection

Disables a projection and saves its checkpoint. A disabled projection stays stopped after the server or the projection subsystem restarts.

```swift
try await client.projections(system: .byCategory).disable()
```

## Abort a projection

Stops a projection **without** saving its checkpoint.

```swift
try await client.projections(system: .byCategory).abort()
```

## Reset a projection

Deletes a projection's checkpoint, so it starts again from the beginning and re-emits its events. Streams the projection writes to are soft-deleted.

```swift
try await client.projections(system: .byCategory).reset()
```

## Delete a projection

Deletes a projection. Disable it first — a running projection can't be deleted. The options choose whether the checkpoint, state and emitted streams are deleted too.

```swift
let projection = client.projections(name: "projection")

// A projection must be disabled before it can be deleted.
try await projection.disable()

try await projection.delete {
    $0.deleteEmittedStreams = true
    $0.deleteStateStream = true
    $0.deleteCheckpointStream = true
}
```

## Update a projection

Replaces a projection's query. Updating system projections isn't supported.

```swift
let js = """
fromAll()
    .when({
        $init: function() {
            return {
                count: 0
            };
        },
        $any: function(s, e) {
            s.count += 1;
        }
    })
    .outputState();
"""

try await client.projections(name: "countEvents").update(query: js)
```

## List projections

Returns the details of every projection, user-defined and system. See <doc:#Projection-details> for the fields.

```swift
let details = try await client.projections(of: .anyMode).list()

for detail in details {
    print("\(detail.name), \(detail.status), \(detail.checkpointStatus), \(detail.mode), \(detail.progress)")
}
```

To list only one mode, use `.anyContinuous`, `.anyTransient` or `.onetime` as the target.

## Get status

Returns the details of one projection, or `nil` if it doesn't exist.

```swift
if let detail = try await client.projections(system: .byCategory).detail() {
    print("\(detail.name), \(detail.status), \(detail.checkpointStatus), \(detail.mode), \(detail.progress)")
}
```

## Get state

Decodes a projection's state:

<!-- snippet:toplevel -->
```swift
// The shape of the projection's state
struct CountResult: Codable {
    let count: Int
}
```

```swift
let name = "get_state_example"
let js = """
fromAll()
    .when({
        $init() {
            return {
                count: 0,
            };
        },
        $any(s, e) {
            s.count += 1;
        }
    })
    .outputState();
"""

try await client.projections(of: .continuous(name: name)).create(query: js)

// Give the projection time to process events and build its state.
try await Task.sleep(for: .milliseconds(500))

let state = try await client.projections(name: name).state(of: CountResult.self)
print(state as Any)
```

For a partitioned projection, set `partition` in the closure.

## Get result

Decodes the result of a projection:

```swift
let name = "get_result_example"
let js = """
fromAll()
    .when({
        $init() {
            return {
                count: 0,
            };
        },
        $any(s, e) {
            s.count += 1;
        }
    })
    .transformBy((state) => state.count)
    .outputState();
"""

try await client.projections(of: .continuous(name: name)).create(query: js)

// Give the projection time to process events.
try await Task.sleep(for: .milliseconds(500))

let result = try await client.projections(name: name).result(of: Int.self)
print(result as Any)
```

## Projection details

`list()` and `detail()` return ``Projection/Detail`` values:

| Field | Description |
|-------|-------------|
| `name`, `effectiveName` | The name of the projection |
| `status` | The current status of the projection (see below) |
| `stateReason` | Why the projection is in its current state |
| `checkpointStatus` | The current checkpoint operation: requested, writing |
| `mode` | Continuous, one-time or transient |
| `coreProcessingTime` | Total time, in ms, spent handling events since the last restart |
| `progress` | How far the projection has processed, in percent. Can be -1 after a restart until the next event is processed |
| `writesInProgress` | Write requests to emitted streams in progress; each can be a batch of events |
| `readsInProgress` | Read requests in progress |
| `partitionsCached` | Cached projection partitions |
| `position` | Position of the last processed event |
| `lastCheckpoint` | Position of the last checkpoint |
| `eventsProcessedAfterRestart` | Events processed since the last restart |
| `bufferedEvents` | Events in the read buffer |
| `writePendingEventsBeforeCheckpoint` | Events waiting to be written to emitted streams before the pending checkpoint can be written |
| `writePendingEventsAfterCheckpoint` | Events written to emitted streams since the last checkpoint |
| `version` | Internal; increases when the projection is edited or reset |
| `epoch` | Internal; increases when the projection is reset |

The status is one of the following. The first three are the common ones; the rest are transient while the projection starts or stops.

| Value | Description |
|-------|-------------|
| Running | Running and processing events |
| Stopped | Stopped; not processing new events |
| Faulted | An error occurred; `stateReason` has the details. Not processing events |
| Initial | The initial state, before the projection is fully initialised |
| Suspended | Suspended while stopping; not processing events |
| LoadStateRequested | Retrieving its state while starting |
| StateLoaded | State loaded while starting |
| Subscribed | Subscribed to its readers while starting |
| FaultedStopping | Stopping because of an error |
| Stopping | Stopping |
| CompletingPhase | Stopping |
| PhaseCompleted | Stopping |

## Architecture

For details on the target-based design of the Projections API, see <doc:ProjectionsTarget-design>.
