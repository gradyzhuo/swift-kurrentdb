# ``EventStoreDB``

@Options(scope: local) {
    @TopicsVisualStyle(hidden)
}

The EventStoreDB Database Client SDK connected by `gRPC`.

## Usage

### Appending Event

```swift
// Import packages of KurrentDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Create the data array of events.
let events:[EventData] = [
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1164")!, eventType: "ItemAdded", payload: ["Description": "Xbox One S 1TB (Console)"]),
    .init(id: .init(uuidString: "b989fe21-9469-4017-8d71-9820b8dd1174")!, eventType: "ItemAdded", payload: "Gears of War 4")
        ]

// Create an identifier of stream
let streamIdentifier = StreamIdentifier(name: "stream_for_testing")

// Build a streams client.
let client = EventStoreDBClient(settings: .localhost())

// Append two events with one response
let appendResponse = try await client.appendStream(to: streamIdentifier, events: events) { options in
    options.revision(expected: .any)
}

print("The latest revision of events appended:", appendResponse.currentRevision!)
```

### Read Event

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Create an identifier of stream.
let streamIdentifier = StreamIdentifier(name: "stream_for_testing")

// Build a streams client.
let client = EventStoreDBClient(settings: settings)

// Read events from stream.
let readResponses = try await client.readStream(to: streamIdentifier, cursor: .start) { options in
    options.set(resolveLinks: true)
}

// loop it.
for try await response in readResponses {
    //handle response
}
```

### PersistentSubscriptions
#### Create

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = EventStoreDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"

// Create it to specified identifier of streams.
try await client.createPersistentSubscription(to: streamIdentifier, groupName: groupName)
```

#### Subscribe

```swift
// Import packages of EventStoreDB.
import EventStoreDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = EventStoreDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"


// Subscribe to stream or all, and get a subscription.
let subscription = try await client.subscribePersistentSubscription(to: .specified(streamIdentifier), groupName: groupName)

// Loop all results by subscription.events
for try await result in subscription.events {
    //handle result
    // ...
    
    // ack the readEvent if succeed
    try await subscription.ack(readEvents: result.event)
    // else nack thr readEvent if not succeed.
    // try await subscription.nack(readEvents: result.event, action: .park, reason: "It's failed.")
}
```
