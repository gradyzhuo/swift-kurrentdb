//
//  KurrentDBClient+PersistentSubscriptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//

// MARK: - Internal Persistent Subscription Accessor

extension KurrentDBClient {
    /// Returns a persistent subscriptions interface for cluster-wide operations.
    package var persistentSubscriptions: PersistentSubscriptions<PersistentSubscription.All> {
        .init(target: .all, selector: selector, callOptions: defaultCallOptions)
    }
}

// MARK: - Persistent Subscription Lifecycle Operations

extension KurrentDBClient {
    /// Creates a persistent subscription group for a specific stream with competing consumer semantics.
    ///
    /// Persistent subscriptions enable competing consumer patterns where multiple clients can subscribe
    /// to the same subscription group and have events distributed among them. The server tracks the
    /// group's position in the stream, handles retries for failed events, and provides at-least-once
    /// delivery guarantees. This is ideal for workload distribution and fault-tolerant event processing.
    ///
    /// ## Competing Consumers
    ///
    /// When multiple clients connect to the same subscription group:
    /// - Events are distributed round-robin across connected consumers
    /// - Each event is delivered to exactly one consumer in the group (unless NAKed and retried)
    /// - The server maintains the group's checkpoint position
    /// - Failed consumers do not lose events; the server redistributes their pending events
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure allows extensive customization:
    /// - **Start Position**: Where to begin reading (start, end, position)
    /// - **Message Timeout**: How long to wait for ACK before retrying
    /// - **Max Retry Count**: Number of retries before parking failed events
    /// - **Buffer Size**: Number of events to buffer per consumer
    /// - **Strategy**: Round-robin, dispatch to single, or pinned consumer
    /// - **Live Buffer Size**: In-memory buffer for live events
    /// - **Read Batch Size**: Number of events to read from disk per batch
    /// - **Checkpoint Settings**: Checkpoint interval and thresholds
    ///
    /// ## Subscription Lifecycle
    ///
    /// 1. **Create**: Define the subscription group and configuration
    /// 2. **Subscribe**: Connect consumers to receive events
    /// 3. **Process**: Handle events and ACK/NAK/Retry as needed
    /// 4. **Update**: Modify configuration while preserving checkpoint
    /// 5. **Delete**: Remove the subscription group entirely
    ///
    /// ## Use Cases
    ///
    /// - Distributing workload across multiple worker processes
    /// - Building fault-tolerant event processors
    /// - Implementing message queue semantics on event streams
    /// - Processing events with automatic retry and dead-letter support
    /// - Scaling event consumers horizontally
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.createPersistentSubscription(
    ///     stream: .init(name: "order-events"),
    ///     groupName: "order-processing-workers"
    /// ) {
    ///     $0.startFrom(revision: .start)
    ///       .messageTimeout(seconds: 30)
    ///       .maxRetryCount(5)
    ///       .bufferSize(20)
    ///       .checkpointAfter(seconds: 10)
    /// }
    ///
    /// // Multiple consumers can now connect
    /// let subscription = try await client.subscribePersistentSubscription(
    ///     stream: .init(name: "order-events"),
    ///     groupName: "order-processing-workers"
    /// )
    ///
    /// for try await event in subscription {
    ///     do {
    ///         try await processOrder(event)
    ///         try await subscription.acknowledge(event)
    ///     } catch {
    ///         try await subscription.nack(event, action: .retry)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The stream to create the subscription on. Use `StreamIdentifier(name:)`
    ///     for named streams or construct with other stream targeting options.
    ///   - groupName: Unique name for the subscription group. Must be unique per stream. Use
    ///     descriptive names indicating the consumer's purpose (e.g., "email-sender", "analytics-processor").
    ///   - configure: Optional closure to configure subscription behavior. Defaults to standard
    ///     settings with start position at stream beginning.
    ///
    /// - Throws: `KurrentError.alreadyExists` if a subscription group with this name already exists on the stream.
    ///   `KurrentError.accessDenied` if the user lacks subscription management permissions.
    ///   `KurrentError.invalidArgument` if group name is invalid or configuration is malformed.
    ///   `KurrentError.notFound` if the specified stream does not exist (depending on settings).
    ///
    /// - Note: Creating a persistent subscription does not automatically start consuming events.
    ///   Consumers must explicitly call `subscribePersistentSubscription()` to connect and receive events.
    ///
    /// - Warning: Subscription groups consume server resources even when no consumers are connected.
    ///   Delete unused subscription groups to free resources.
    ///
    /// - SeeAlso: `subscribePersistentSubscription(stream:groupName:configure:)`,
    ///   `updatePersistentSubscription(stream:groupName:configure:)`,
    ///   `deletePersistentSubscription(stream:groupName:)`
    public func createPersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Creates a persistent subscription group for the `$all` stream across the entire event store.
    ///
    /// Persistent subscriptions on `$all` enable competing consumers to process events from every stream
    /// in the database. This is useful for cross-cutting concerns like audit logging, analytics, or
    /// system-wide event handlers that need visibility into all domain events. Events are distributed
    /// among connected consumers with automatic retry and checkpoint management.
    ///
    /// ## $all Stream Characteristics
    ///
    /// - **Global Scope**: Receives events from every stream in the event store
    /// - **System Events**: Can filter out internal system events using configuration
    /// - **High Volume**: May have significant throughput; configure buffer sizes appropriately
    /// - **Position Tracking**: Uses global commit positions instead of stream revisions
    ///
    /// ## Configuration Options
    ///
    /// Similar to stream-specific subscriptions, with additional `$all`-specific options:
    /// - **Filter**: Exclude system events or filter by event type/stream prefix
    /// - **Start Position**: Global commit position in the event store
    /// - **Checkpoint Strategy**: Configure based on expected event volume
    /// - **Consumer Strategy**: Distribute work among competing consumers
    ///
    /// ## Use Cases
    ///
    /// - Global audit logging across all streams
    /// - System-wide analytics and reporting
    /// - Event replication to external systems
    /// - Building comprehensive read models spanning multiple aggregates
    /// - Cross-stream process managers and sagas
    ///
    /// ## Example
    ///
    /// ```swift
    /// try await client.createPersistentSubscriptionToAllStream(
    ///     groupName: "global-audit-logger"
    /// ) {
    ///     $0.startFrom(position: .start)
    ///       .filter(excludeSystemEvents: true)
    ///       .messageTimeout(seconds: 60)
    ///       .maxRetryCount(3)
    ///       .checkpointAfter(seconds: 30)
    /// }
    ///
    /// // Consumer processes all events from all streams
    /// let subscription = try await client.subscribePersistentSubscriptionToAllStreams(
    ///     groupName: "global-audit-logger"
    /// )
    ///
    /// for try await event in subscription {
    ///     await auditLog.record(event)
    ///     try await subscription.acknowledge(event)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - groupName: Unique name for the subscription group across the `$all` stream.
    ///   - configure: Optional closure to configure subscription behavior, including filtering
    ///     and position settings.
    ///
    /// - Throws: `KurrentError.alreadyExists` if a subscription group with this name already exists on `$all`.
    ///   `KurrentError.accessDenied` if the user lacks subscription management permissions.
    ///   `KurrentError.invalidArgument` if configuration is malformed.
    ///
    /// - Warning: `$all` subscriptions can generate very high event volumes. Configure appropriate
    ///   filters and buffer sizes to prevent overwhelming consumers and consuming excessive server resources.
    ///
    /// - SeeAlso: `subscribePersistentSubscriptionToAllStreams(groupName:configure:)`,
    ///   `updatePersistentSubscriptionToAllStream(groupName:configure:)`
    public func createPersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Create.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Updates configuration for an existing persistent subscription group while preserving its checkpoint.
    ///
    /// Updating a persistent subscription modifies its operational parameters without losing the group's
    /// current position in the stream. This allows you to tune subscription behavior, adjust timeouts,
    /// change retry policies, or modify buffer sizes based on production performance data. Connected
    /// consumers may experience brief disruption as the new configuration takes effect.
    ///
    /// ## Updateable Settings
    ///
    /// You can modify most subscription parameters:
    /// - **Message Timeout**: ACK deadline before retry
    /// - **Max Retry Count**: Retry attempts before parking
    /// - **Buffer Sizes**: Live and read buffer capacities
    /// - **Checkpoint Configuration**: Frequency and thresholds
    /// - **Consumer Strategy**: Distribution algorithm
    /// - **Batch Size**: Events per read operation
    ///
    /// ## Non-Updateable Settings
    ///
    /// Some settings cannot be changed after creation:
    /// - **Group Name**: Immutable; create a new subscription with a different name instead
    /// - **Start Position**: Initial position is set at creation; use reset to replay from a new position
    ///
    /// ## Update Behavior
    ///
    /// When updated:
    /// - The subscription checkpoint is preserved
    /// - Connected consumers may be briefly disconnected
    /// - In-flight events may be redelivered based on new timeout settings
    /// - Configuration changes take effect immediately
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Original configuration with conservative timeouts
    /// try await client.createPersistentSubscription(
    ///     stream: .init(name: "orders"),
    ///     groupName: "order-processor"
    /// ) {
    ///     $0.messageTimeout(seconds: 30)
    ///       .maxRetryCount(5)
    /// }
    ///
    /// // After observing production behavior, increase timeout
    /// try await client.updatePersistentSubscription(
    ///     stream: .init(name: "orders"),
    ///     groupName: "order-processor"
    /// ) {
    ///     $0.messageTimeout(seconds: 120)
    ///       .maxRetryCount(10)
    ///       .bufferSize(50)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The stream containing the subscription group to update.
    ///   - groupName: The name of the subscription group to modify.
    ///   - configure: Closure to configure new subscription settings. Only specified options are updated;
    ///     unspecified options retain their current values.
    ///
    /// - Throws: `KurrentError.notFound` if no subscription group exists with the specified name on the stream.
    ///   `KurrentError.accessDenied` if the user lacks subscription management permissions.
    ///   `KurrentError.invalidArgument` if the configuration is malformed.
    ///
    /// - Note: Connected consumers may need to reconnect after configuration updates. Design consumer
    ///   code to handle transient disconnections gracefully.
    ///
    /// - SeeAlso: `createPersistentSubscription(stream:groupName:configure:)`,
    ///   `deletePersistentSubscription(stream:groupName:)`
    public func updatePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Updates configuration for a persistent subscription group on the `$all` stream.
    ///
    /// Modifies operational parameters for an existing `$all` subscription group while preserving
    /// its checkpoint position. This is useful for tuning performance, adjusting retry behavior,
    /// or changing filters based on observed event volumes and processing patterns.
    ///
    /// ## All-Stream Specific Updates
    ///
    /// In addition to standard subscription settings, you can update:
    /// - **Event Filters**: Modify system event exclusion or type/prefix filters
    /// - **Checkpoint Frequency**: Adjust based on global event volume
    /// - **Buffer Sizes**: Tune for high-throughput scenarios
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Update filter to exclude specific event types
    /// try await client.updatePersistentSubscriptionToAllStream(
    ///     groupName: "analytics-processor"
    /// ) {
    ///     $0.filter(excludeSystemEvents: true)
    ///       .filter(eventTypePrefix: "Analytics")
    ///       .messageTimeout(seconds: 90)
    ///       .checkpointAfter(seconds: 60)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group to update.
    ///   - configure: Closure to configure new subscription settings including filters.
    ///
    /// - Throws: `KurrentError.notFound` if no subscription group exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks subscription management permissions.
    ///   `KurrentError.invalidArgument` if the configuration is malformed.
    ///
    /// - SeeAlso: `createPersistentSubscriptionToAllStream(groupName:configure:)`,
    ///   `deletePersistentSubscriptionToAllStream(groupName:)`
    public func updatePersistentSubscriptionToAllStream(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Subscribes a consumer to a persistent subscription group, receiving events in competing consumer mode.
    ///
    /// Connects this consumer instance to an existing persistent subscription group, enabling it to
    /// receive events distributed by the server. Events are automatically distributed among all connected
    /// consumers in the group using the configured strategy (round-robin, pinned, etc.). The consumer
    /// must acknowledge (ACK) or negatively acknowledge (NAK) each event to control retry behavior.
    ///
    /// ## Event Processing
    ///
    /// The returned subscription object provides an `AsyncSequence` of events:
    ///
    /// ```swift
    /// for try await event in subscription {
    ///     // Process event
    ///     // Must ACK, NAK, or RETRY
    /// }
    /// ```
    ///
    /// ## Acknowledgment Actions
    ///
    /// Each event must be acknowledged with one of:
    /// - **ACK**: Event processed successfully, advance checkpoint
    /// - **NAK**: Event processing failed, retry based on subscription settings
    /// - **RETRY**: Explicitly retry this event immediately
    /// - **PARK**: Move event to parked queue for manual intervention
    /// - **SKIP**: Skip this event without retrying
    ///
    /// ## Connection Management
    ///
    /// - Multiple consumers can connect to the same group simultaneously
    /// - The server distributes events among connected consumers
    /// - If a consumer disconnects, its pending events are redistributed
    /// - Connection errors trigger automatic reconnection (if configured)
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure allows:
    /// - **Buffer Size**: Number of events to prefetch for this consumer
    /// - **Consumer Name**: Identifier for this consumer instance in telemetry
    /// - **Auto-ACK**: Automatically acknowledge events (not recommended)
    ///
    /// ## Use Cases
    ///
    /// - Implementing competing consumers for workload distribution
    /// - Building fault-tolerant event processors
    /// - Processing domain events with automatic retry
    /// - Scaling event consumption horizontally
    ///
    /// ## Example
    ///
    /// ```swift
    /// let subscription = try await client.subscribePersistentSubscription(
    ///     stream: .init(name: "payment-events"),
    ///     groupName: "payment-processor"
    /// ) {
    ///     $0.bufferSize(10)
    ///       .consumerName("payment-worker-1")
    /// }
    ///
    /// for try await event in subscription {
    ///     do {
    ///         let payment = try event.decode(to: Payment.self)
    ///         try await processPayment(payment)
    ///
    ///         // Acknowledge successful processing
    ///         try await subscription.acknowledge(event)
    ///     } catch let error as RecoverableError {
    ///         // Retry on recoverable errors
    ///         try await subscription.nack(event, action: .retry)
    ///     } catch {
    ///         // Park on unrecoverable errors for manual review
    ///         try await subscription.nack(event, action: .park)
    ///     }
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The stream containing the subscription group.
    ///   - groupName: The name of the subscription group to join.
    ///   - configure: Optional closure to configure consumer-specific read options.
    ///
    /// - Returns: A subscription object conforming to `AsyncSequence` that yields events and
    ///   provides methods for acknowledgment (ACK/NAK/RETRY).
    ///
    /// - Throws: `KurrentError.notFound` if no subscription group exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks subscription read permissions.
    ///   `KurrentError.maximumSubscribersReached` if the group has reached its consumer limit.
    ///
    /// - Warning: Failing to acknowledge events causes them to time out and retry, potentially
    ///   creating processing backlogs. Always ACK or NAK every event received.
    ///
    /// - SeeAlso: `createPersistentSubscription(stream:groupName:configure:)`,
    ///   `PersistentSubscription.acknowledge(_:)`, `PersistentSubscription.nack(_:action:)`
    public func subscribePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamIdentifier))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Subscribes a consumer to a persistent subscription group on the `$all` stream.
    ///
    /// Connects this consumer to a subscription group processing events from the entire event store.
    /// Events from all streams are distributed among connected consumers, enabling global event handlers,
    /// audit logging, or cross-cutting concerns that span multiple bounded contexts.
    ///
    /// ## All-Stream Characteristics
    ///
    /// - **Global Scope**: Receives events from every stream
    /// - **High Volume**: May receive significant event throughput
    /// - **Filtering**: Respects filters configured on the subscription group
    /// - **System Events**: Can include or exclude system events based on configuration
    ///
    /// ## Example
    ///
    /// ```swift
    /// let subscription = try await client.subscribePersistentSubscriptionToAllStreams(
    ///     groupName: "global-audit-logger"
    /// ) {
    ///     $0.bufferSize(20)
    ///       .consumerName("audit-worker-1")
    /// }
    ///
    /// for try await event in subscription {
    ///     // Log all events across the system
    ///     await auditLog.record(
    ///         stream: event.streamIdentifier,
    ///         eventType: event.eventType,
    ///         timestamp: event.created
    ///     )
    ///
    ///     try await subscription.acknowledge(event)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - groupName: The name of the subscription group to join on the `$all` stream.
    ///   - configure: Optional closure to configure consumer-specific read options.
    ///
    /// - Returns: A subscription object yielding events from all streams.
    ///
    /// - Throws: `KurrentError.notFound` if no subscription group exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks subscription read permissions.
    ///   `KurrentError.maximumSubscribersReached` if the group has reached its consumer limit.
    ///
    /// - Warning: `$all` subscriptions can generate very high event volumes. Ensure consumers
    ///   can handle the expected throughput or configure appropriate filters on the subscription group.
    ///
    /// - SeeAlso: `createPersistentSubscriptionToAllStream(groupName:configure:)`
    public func subscribePersistentSubscriptionToAllStreams(groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.AllStream>.AllStream.Read.Options = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<PersistentSubscription.AllStream>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .all)
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Deletes a persistent subscription group, removing all configuration and checkpoint data.
    ///
    /// Permanently removes a persistent subscription group from the stream, including its checkpoint
    /// position, retry counters, and parked events. All connected consumers are disconnected and cannot
    /// reconnect to this group. This operation is irreversible; the subscription must be recreated from
    /// scratch if needed again.
    ///
    /// ## Deletion Effects
    ///
    /// When deleted:
    /// - All checkpoint data is permanently removed
    /// - Connected consumers are immediately disconnected
    /// - Parked events are lost
    /// - Retry state and counters are cleared
    /// - Group configuration is removed
    ///
    /// ## Safety Considerations
    ///
    /// Before deleting a subscription:
    /// 1. Verify no consumers are actively processing events
    /// 2. Ensure parked events have been handled or are no longer needed
    /// 3. Consider disabling the subscription first to prevent new connections
    /// 4. Document the reason for deletion for operational records
    ///
    /// ## Use Cases
    ///
    /// - Removing obsolete subscription groups no longer needed
    /// - Cleaning up after migrating to new subscription configurations
    /// - Decommissioning deprecated event processors
    /// - Freeing server resources from unused subscriptions
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Verify no active consumers
    /// let subscriptions = try await client.listPersistentSubscriptions(
    ///     stream: .init(name: "orders")
    /// )
    ///
    /// let targetGroup = subscriptions.first {
    ///     $0.groupName == "old-order-processor"
    /// }
    ///
    /// if let group = targetGroup, group.connections.isEmpty {
    ///     // Safe to delete - no active consumers
    ///     try await client.deletePersistentSubscription(
    ///         stream: .init(name: "orders"),
    ///         groupName: "old-order-processor"
    ///     )
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - streamIdentifier: The stream containing the subscription group to delete.
    ///   - groupName: The name of the subscription group to remove.
    ///
    /// - Throws: `KurrentError.notFound` if no subscription group exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks subscription management permissions.
    ///
    /// - Warning: Deletion is permanent and cannot be undone. Checkpoint positions and parked
    ///   events are lost. Create backups of critical subscription configurations before deleting.
    ///
    /// - SeeAlso: `createPersistentSubscription(stream:groupName:configure:)`,
    ///   `listPersistentSubscriptions(stream:)`
    public func deletePersistentSubscription(stream streamIdentifier: StreamIdentifier, groupName: String) async throws(KurrentError) {
        try await streams(of: .specified(streamIdentifier))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Deletes a persistent subscription group from the `$all` stream.
    ///
    /// Permanently removes a subscription group processing events from the entire event store.
    /// All connected consumers are disconnected, and all checkpoint and retry state is lost.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Delete global analytics subscription that's no longer needed
    /// try await client.deletePersistentSubscriptionToAllStream(
    ///     groupName: "legacy-analytics"
    /// )
    /// ```
    ///
    /// - Parameter groupName: The name of the subscription group to delete.
    ///
    /// - Throws: `KurrentError.notFound` if no subscription group exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks subscription management permissions.
    ///
    /// - Warning: Deletion is permanent. Checkpoint positions for processing the entire event
    ///   store are lost and cannot be recovered.
    ///
    /// - SeeAlso: `createPersistentSubscriptionToAllStream(groupName:configure:)`
    public func deletePersistentSubscriptionToAllStream(groupName: String) async throws(KurrentError) {
        try await streams(of: .all)
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Lists all persistent subscription groups configured for a specific stream.
    ///
    /// Retrieves detailed information about all subscription groups on the specified stream, including
    /// configuration settings, checkpoint positions, connected consumer counts, and parked event statistics.
    /// This is essential for monitoring subscription health, troubleshooting issues, and understanding
    /// consumption patterns.
    ///
    /// ## Returned Information
    ///
    /// Each `SubscriptionInfo` includes:
    /// - **Group Name**: Unique identifier for the subscription
    /// - **Event Source**: The stream being consumed
    /// - **Configuration**: Timeout, retry, and buffer settings
    /// - **Status**: Current operational state
    /// - **Checkpoint Position**: Last acknowledged position
    /// - **Connection Count**: Number of active consumers
    /// - **Parked Event Count**: Events waiting for manual intervention
    /// - **Average Processing Time**: Performance metrics
    ///
    /// ## Use Cases
    ///
    /// - Monitoring subscription health dashboards
    /// - Discovering configured subscription groups
    /// - Troubleshooting event processing issues
    /// - Auditing subscription configurations
    /// - Identifying subscriptions with parked events
    ///
    /// ## Example
    ///
    /// ```swift
    /// let subscriptions = try await client.listPersistentSubscriptions(
    ///     stream: .init(name: "orders")
    /// )
    ///
    /// for sub in subscriptions {
    ///     print("Group: \(sub.groupName)")
    ///     print("Connections: \(sub.connectionCount)")
    ///     print("Checkpoint: \(sub.lastCheckpointedEventPosition)")
    ///
    ///     if sub.parkedMessageCount > 0 {
    ///         print("WARNING: \(sub.parkedMessageCount) parked events need attention")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter streamIdentifier: The stream to query for subscription groups.
    ///
    /// - Returns: An array of subscription information for all groups on the stream. Returns an empty
    ///   array if no subscription groups exist for this stream.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks subscription read permissions.
    ///   `KurrentError.notFound` if the specified stream does not exist (depending on server configuration).
    ///
    /// - SeeAlso: `listAllPersistentSubscription()`, `PersistentSubscription.SubscriptionInfo`
    public func listPersistentSubscriptions(stream streamIdentifier: StreamIdentifier) async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(streamIdentifier))
    }

    /// Lists all persistent subscription groups configured for the `$all` stream.
    ///
    /// Retrieves information about subscription groups processing events from the entire event store.
    /// These are typically global event handlers, audit loggers, or cross-cutting concerns.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let allSubscriptions = try await client.listPersistentSubscriptionsToAllStream()
    ///
    /// for sub in allSubscriptions {
    ///     print("Global subscription: \(sub.groupName)")
    ///     print("Event position: \(sub.lastCheckpointedEventPosition)")
    ///     print("Active consumers: \(sub.connectionCount)")
    /// }
    /// ```
    ///
    /// - Returns: An array of subscription information for all groups on the `$all` stream.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks subscription read permissions.
    ///
    /// - SeeAlso: `listAllPersistentSubscription()`, `createPersistentSubscriptionToAllStream(groupName:configure:)`
    public func listPersistentSubscriptionsToAllStream() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(.all))
    }

    /// Lists all persistent subscription groups across all streams in the event store.
    ///
    /// Retrieves comprehensive information about every persistent subscription group in the system,
    /// regardless of which stream they consume. This provides a global view of all competing consumer
    /// groups and is useful for cluster-wide monitoring, auditing, and capacity planning.
    ///
    /// ## Use Cases
    ///
    /// - Building subscription management dashboards
    /// - Global health monitoring
    /// - Identifying resource-intensive subscriptions
    /// - Auditing subscription configurations across the cluster
    /// - Discovering all active consumer groups
    ///
    /// ## Example
    ///
    /// ```swift
    /// let allSubscriptions = try await client.listAllPersistentSubscription()
    ///
    /// print("Total subscription groups: \(allSubscriptions.count)")
    ///
    /// // Find subscriptions with parked events
    /// let withParkedEvents = allSubscriptions.filter {
    ///     $0.parkedMessageCount > 0
    /// }
    ///
    /// for sub in withParkedEvents {
    ///     print("⚠️ \(sub.groupName) on \(sub.eventSource) has \(sub.parkedMessageCount) parked events")
    /// }
    ///
    /// // Find idle subscriptions
    /// let idleSubscriptions = allSubscriptions.filter {
    ///     $0.connectionCount == 0
    /// }
    ///
    /// print("Idle subscriptions (no consumers): \(idleSubscriptions.count)")
    /// ```
    ///
    /// - Returns: An array of subscription information for all groups across all streams.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks subscription read permissions.
    ///
    /// - Note: This operation queries the entire cluster and may be slower than stream-specific queries
    ///   in systems with many subscription groups.
    ///
    /// - SeeAlso: `listPersistentSubscriptions(stream:)`, `listPersistentSubscriptionsToAllStream()`
    public func listAllPersistentSubscription() async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .allSubscriptions)
    }

    /// Restarts the entire persistent subscription subsystem across the cluster.
    ///
    /// Stops all persistent subscriptions, clears in-memory state, and reinitializes the subscription
    /// manager. All subscription groups are then restarted from their last checkpoints. This is a
    /// disruptive cluster-wide operation intended for recovery from subsystem failures or after
    /// configuration changes requiring a full restart.
    ///
    /// ## Restart Process
    ///
    /// During restart:
    /// 1. All active subscriptions are stopped and consumers disconnected
    /// 2. Subscription subsystem state is cleared
    /// 3. Subscription manager reinitializes
    /// 4. All subscription groups reload from persistent storage
    /// 5. Consumers can reconnect and resume from last checkpoints
    ///
    /// ## Impact
    ///
    /// - **Consumer Disconnection**: All connected consumers across all groups are disconnected
    /// - **Processing Interruption**: Event processing stops temporarily
    /// - **Checkpoint Preservation**: All checkpoints are preserved; no event loss
    /// - **Downtime**: Brief unavailability while subsystem restarts
    ///
    /// ## Use Cases
    ///
    /// - Recovering from persistent subscription subsystem failures
    /// - Applying subscription subsystem configuration changes
    /// - Clearing subscription manager memory leaks
    /// - Forcing reload of subscription definitions
    /// - Troubleshooting subscription coordination issues
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Restart subsystem after detecting failures
    /// try await client.restartPersistentSubscriptionSubsystem()
    ///
    /// // Wait for subsystem to stabilize
    /// try await Task.sleep(for: .seconds(10))
    ///
    /// // Verify subscriptions are healthy
    /// let subscriptions = try await client.listAllPersistentSubscription()
    ///
    /// for sub in subscriptions {
    ///     if sub.connectionCount == 0 {
    ///         print("WARNING: \(sub.groupName) has no consumers after restart")
    ///     }
    /// }
    /// ```
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the subsystem cannot be restarted.
    ///
    /// - Warning: This is a cluster-wide disruptive operation affecting all persistent subscriptions
    ///   simultaneously. All consumers will be disconnected. Only use during maintenance windows or
    ///   when recovering from subsystem failures.
    ///
    /// - Warning: Requires administrative permissions. This operation should be restricted to
    ///   operators and automated recovery systems.
    ///
    /// - SeeAlso: `listAllPersistentSubscription()`
    public func restartPersistentSubscriptionSubsystem() async throws(KurrentError) {
        try await persistentSubscriptions.restartSubsystem()
    }

    // MARK: - Convenience Overloads (String Stream Names)

    /// Creates a persistent subscription group for a stream identified by name string.
    ///
    /// Convenience method that accepts a stream name string instead of a `StreamIdentifier`.
    /// Functionally identical to `createPersistentSubscription(stream:groupName:configure:)`
    /// with `StreamIdentifier(name:)`.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream to create the subscription on.
    ///   - groupName: Unique name for the subscription group.
    ///   - configure: Optional closure to configure subscription behavior.
    ///
    /// - Throws: `KurrentError.alreadyExists`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`
    ///
    /// - SeeAlso: `createPersistentSubscription(stream:groupName:configure:)`
    public func createPersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Create.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .create(options: options)
    }

    /// Updates configuration for a persistent subscription group on a stream identified by name.
    ///
    /// Convenience method that accepts a stream name string instead of a `StreamIdentifier`.
    /// Functionally identical to `updatePersistentSubscription(stream:groupName:configure:)`
    /// with `StreamIdentifier(name:)`.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream containing the subscription group.
    ///   - groupName: The name of the subscription group to update.
    ///   - configure: Closure to configure new subscription settings.
    ///
    /// - Throws: `KurrentError.notFound`, `KurrentError.accessDenied`, `KurrentError.invalidArgument`
    ///
    /// - SeeAlso: `updatePersistentSubscription(stream:groupName:configure:)`
    public func updatePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Update.Options = { $0 }) async throws(KurrentError) {
        let options = configure(.init())
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .update(options: options)
    }

    /// Subscribes to a persistent subscription group on a stream identified by name.
    ///
    /// Convenience method that accepts a stream name string instead of a `StreamIdentifier`.
    /// Functionally identical to `subscribePersistentSubscription(stream:groupName:configure:)`
    /// with `StreamIdentifier(name:)`.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream containing the subscription group.
    ///   - groupName: The name of the subscription group to join.
    ///   - configure: Optional closure to configure consumer-specific read options.
    ///
    /// - Returns: A subscription object yielding events and providing acknowledgment methods.
    ///
    /// - Throws: `KurrentError.notFound`, `KurrentError.accessDenied`, `KurrentError.maximumSubscribersReached`
    ///
    /// - SeeAlso: `subscribePersistentSubscription(stream:groupName:configure:)`
    public func subscribePersistentSubscription(stream streamName: String, groupName: String, configure: @Sendable (PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options) -> PersistentSubscriptions<PersistentSubscription.Specified>.SpecifiedStream.Read.Options = { $0 }) async throws(KurrentError) -> PersistentSubscriptions<PersistentSubscription.Specified>.Subscription {
        let options = configure(.init())
        let stream = streams(of: .specified(streamName))
        return try await stream.persistentSubscriptions(group: groupName).subscribe(options: options)
    }

    /// Deletes a persistent subscription group from a stream identified by name.
    ///
    /// Convenience method that accepts a stream name string instead of a `StreamIdentifier`.
    /// Functionally identical to `deletePersistentSubscription(stream:groupName:)`
    /// with `StreamIdentifier(name:)`.
    ///
    /// - Parameters:
    ///   - streamName: The name of the stream containing the subscription group.
    ///   - groupName: The name of the subscription group to delete.
    ///
    /// - Throws: `KurrentError.notFound`, `KurrentError.accessDenied`
    ///
    /// - Warning: Deletion is permanent and cannot be undone.
    ///
    /// - SeeAlso: `deletePersistentSubscription(stream:groupName:)`
    public func deletePersistentSubscription(stream streamName: String, groupName: String) async throws(KurrentError) {
        try await streams(of: .specified(streamName))
            .persistentSubscriptions(group: groupName)
            .delete()
    }

    /// Lists persistent subscription groups on a stream identified by name.
    ///
    /// Convenience method that accepts a stream name string instead of a `StreamIdentifier`.
    /// Functionally identical to `listPersistentSubscriptions(stream:)`
    /// with `StreamIdentifier(name:)`.
    ///
    /// - Parameter streamName: The name of the stream to query for subscription groups.
    ///
    /// - Returns: An array of subscription information for all groups on the stream.
    ///
    /// - Throws: `KurrentError.accessDenied`, `KurrentError.notFound`
    ///
    /// - SeeAlso: `listPersistentSubscriptions(stream:)`
    public func listPersistentSubscriptions(stream streamName: String) async throws(KurrentError) -> [PersistentSubscription.SubscriptionInfo] {
        try await persistentSubscriptions.list(for: .stream(streamName))
    }
}
