# ``KurrentDB``

@Options(scope: local) {
    @TopicsVisualStyle(hidden)
}

The Kurrent Database Client SDK connected by `gRPC`.

## Articles 
- <doc:Getting-started>
- <doc:Appending-events>

## Usage

Create a ``KurrentDBClient`` instance with client settings and the number of threads.
Then, interact with a specific stream by creating a `Streams` client for it.

### Streams
```swift
let clientSettings: ClientSettings = "esdb://localhost:2113?tls=false" // Initialize with actual settings
let client = KurrentDBClient(settings: clientSettings, numberOfThreads: 2)

// Define the stream identifier (this can be either a specific stream or all streams)
let streamIdentifier = StreamIdentifier("streamName") // Use a specified stream identifier

// Accessing the 'Streams' client for a specific stream
let streamsClient = client.streams(of: .specified(streamIdentifier))

// Perform an action like appending events to the stream
let eventData = EventData(type: "eventType", data: "eventData")
try await streamsClient.append(events: [eventData])
```

### PersistentSubscriptions

```swift
// Import packages of EventStoreDB.
import KurrentDB

// Using a client settings for a single node configuration by parsing a connection string.
let settings: ClientSettings = .localhost()

// Build a persistentSubscriptions client.
let client = KurrentDBClient(settings: settings)

// the stream identifier to subscribe.
let streamIdentifier = StreamIdentifier(name: UUID().uuidString)

// the group of subscription
let groupName = "myGroupTest"

let persistentSubscription = client.persistentSubscriptions(of: .specified(streamIdentifier, group: groupName))

// Create it to specified identifier of streams.
try await persistentSubscription.create(options: .init())


let subscription = try await persistentSubscription.subscribe(options: .init())

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


