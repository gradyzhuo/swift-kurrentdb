# Projections
The various gRPC client APIs include dedicated clients that allow you to manage projections.


## Creating a client
Projection management operations are exposed through a dedicated client.

```swift
let settings: ClientSettings = .localhost()
                                    .defaultUserCredentials(.init(username: "admin", password: "changeit"))
let client = KurrentDBClient(settings: settings)
```

## Create a projection
Creates a projection that runs until the last event in the store, and then continues processing new events as they are appended to the store. The query parameter contains the JavaScript you want created as a projection. Projections have explicit names, and you can enable or disable them via this name.

```swift
import Foundation

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

try await client.createContinuousProjection(name: name, query: js)
```

Trying to create projections with the same name will result in an error:

```swift
do {
    try await client.createContinuousProjection(name: name, query: js)
}catch let error as KurrentError {
    if case .resourceAlreadyExists = error {
        print("\(name) already exists")
    }
}
```

## Restart the subsystem

It is possible to restart the entire projection subsystem using the projections management client API. The user must be in the $ops or $admin group to perform this operation.


```swift
try await client.restartSubsystem()
```

## Enable a projection

Enables an existing projection by name. Once enabled, the projection will start to process events even after restarting the server or the projection subsystem. You must have access to a projection to enable it, see the [ACL documentation](https://docs.kurrent.io/server/v24.10/security/user-authorization.html).

```swift
// by predefined enum.
try await client.enableProjection(name: "$by_category")
```

You can only enable an existing projection. When you try to enable a non-existing projection, you'll get an error:

```swift
do{
    try await client.enableProjection(name: "projection that does not exists")
}catch let error as KurrentError {
    if case .resourceNotFound(let reason) = error {
        print(reason)
    }
}
```

## Disable a projection
Disables a projection, this will save the projection checkpoint. Once disabled, the projection will not process events even after restarting the server or the projection subsystem. You must have access to a projection to disable it, see the [ACL documentation](https://docs.kurrent.io/server/v24.10/security/user-authorization.html).

```swift
try await client.disableProjection(name: "$by_category")
```

You can only disable an existing projection. When you try to disable a non-existing projection, you'll get an error:

```swift
do{
    try await client.disableProjection(name: "projection that does not exists")
}catch let error as KurrentError {
    if case .resourceNotFound(let reason) = error {
        print(reason)
    }
}
```

## Delete a projection

Deletes an existing projection. You must disable the projection before deleting it, running projections cannot be deleted. Deleting a projection includes deleting the checkpoint and the emitted streams.

```swift
let name = "projection"
// A projection must be disabled to allow it to be deleted.
try await client.disableProjection(name: name)

// The projection can now be deleted
try await client.deleteProjection(name: name)
```
You can only delete an existing projection. When you try to delete a non-existing projection, you'll get an error:

```swift
do{
    try await client.deleteProjection(name: "projection that does not exists")
}catch let error as KurrentError {
    if case .resourceNotFound(let reason) = error {
        print(reason)
    }
}
```

## Abort a projection
Aborts a projection, this will not save the projection's checkpoint.

```swift
try await client.abortProjection(name: "$by_category")
```

You can only disable an existing projection. When you try to disable a non-existing projection, you'll get an error:

```swift
do{
    try await client.abortProjection(name: "projection that does not exists")
}catch let error as KurrentError {
    if case .resourceNotFound(let reason) = error {
        print(reason)
    }
}
```

## Reset a projection
Resets a projection, which causes deleting the projection checkpoint. This will force the projection to start afresh and re-emit events. Streams that are written to from the projection will also be soft-deleted.

```swift
try await client.resetProjection(name: "$by_category")
```

You can only disable an existing projection. When you try to disable a non-existing projection, you'll get an error:

```swift
do{
    try await client.resetProjection(name: "projection that does not exists")
}catch let error as KurrentError {
    if case .resourceNotFound(let reason) = error {
        print(reason)
    }
}
```

## Update a projection
Updates a projection with a given name. The query parameter contains the new JavaScript. Updating system projections using this operation is not supported at the moment.


```swift 
let name = "countEvents_Update_\(UUID())"
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

try await client.updateProjection(name: name, query: "fromAll().when()")
```

You can only update an existing projection. When you try to update a non-existing projection, you'll get an error:

```swift
do{
    try await client.updateProjection(name: "projection that does not exists", query: "fromAll().when()")
}catch let error as KurrentError {
    if case .resourceNotFound(let reason) = error {
        print(reason)
    }
}
```

## List all projections
Returns a list of all projections, user defined & system projections. See the projection details section for an explanation of the returned values.

```swift
let details = try await client.listAllProjections()


for try await detail in details {
    print("\(detail.name), \(detail.status), \(detail.checkpointStatus), \(detail.mode), \(detail.progress)")
}
```


## Get status
Gets the status of a named projection. See the projection details section for an explanation of the returned values.

```swift
let detail = try await client.getProjectionDetail("$by_category")

print("\(detail?.name), \(detail?.status), \(detail?.checkpointStatus), \(detail?.mode), \(detail?.progress)")
```

## Get state
Retrieves the state of a projection.

```swift
// Result structure of state 
struct CountResult: Codable {
    let count: Int
}

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

try await client.createContinuousProjection(name: name, query: js)

try await Task.sleep(for: .microseconds(500)) //give it some time to process and have a state.

let state = try await client.getProjectionState(of: CountResult.self, name: name)
print(state)
```

## Get result
Retrieves the result of the named projection and partition.

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

try await client.createContinuousProjection(name: name, query: js)

try await Task.sleep(for: .microseconds(500)) //give it some time to process and have a state.

let result = try await client.getProjectionResult(of: Int.self, name: name)
print(result)
```

## Projection Details
`List all`, `list continuous` and `get status` all return the details and statistics of projections.
|Field|Description|
|-----|-----------|
|Name, EffectiveName|The name of the projection.|
|Status|A human readable string of the current statuses of the projection (see below)|
|StateReason|A human readable string explaining the reason of the current projection state.|
|CheckpointStatus|A human readable string explaining the current operation performed on the checkpoint : requested, writing.|
|Mode|`Continuous`, `OneTime` , `Transient`|
|CoreProcessingTime|The total time, in ms, the projection took to handle events since the last restart|
|Progress|The progress, in %, indicates how far this projection has processed event, in case of a restart this could be -1% or some number. It will be updated as soon as a new event is appended and processed|
|WritesInProgress|The number of write requests to emitted streams currently in progress, these writes can be batches of events|
|ReadsInProgress|The number of read requests currently in progress.|
|PartitionsCached|The number of cached projection partitions.|
|Position|The Position of the last processed event.|
|LastCheckpoint|The Position of the last checkpoint of this projection.|
|EventsProcessedAfterRestart|The number of events processed since the last restart of this projection.|
|BufferedEvents|The number of events in the projection read buffer.|
|WritePendingEventsBeforeCheckpoint|The number of events waiting to be appended to emitted streams before the pending checkpoint can be written.|
|WritePendingEventsAfterCheckpoint|The number of events to be appended to emitted streams since the last checkpoint.|
|Version|This is used internally, the version is increased when the projection is edited or reset.|
|Epoch|This is used internally, the epoch is increased when the projection is reset.|

## Architecture

For details on the target-based design of the Projections API, see <doc:ProjectionsTarget-design>.


The Status string is a combination of the following values. The first 3 are the most common one, as the other one are transient values while the projection is initialised or stopped.
|Value|Description|
|-----|-----------|
|Running|The projection is running and processing events.|
|Stopped|The projection is stopped and is no longer processing new events.|
|Faulted|An error occurred in the projection, StateReason will give the fault details, the projection is not processing events.|
|Initial|This is the initial state, before the projection is fully initialised.|
|Suspended|The projection is suspended and will not process events, this happens while stopping the projection.|
|LoadStateRequested|The state of the projection is being retrieved, this happens while the projection is starting.|
|StateLoaded|The state of the projection is loaded, this happens while the projection is starting.|
|Subscribed|The projection has successfully subscribed to its readers, this happens while the projection is starting.|
|FaultedStopping|This happens before the projection is stopped due to an error in the projection.|
|Stopping|The projection is being stopped.|
|CompletingPhase|This happens while the projection is stopping.|
|PhaseCompleted|This happens while the projection is stopping.|
