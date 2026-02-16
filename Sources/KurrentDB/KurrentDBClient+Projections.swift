//
//  KurrentDBClient+Projections.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/5/23.
//
// MARK: - Internal Projection Factory Methods

extension KurrentDBClient {
    /// Creates a projections interface targeting all projections.
    package func projections() -> Projections<AnyProjectionsTarget> {
        .init(target: .init(), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface for a specific target type.
    package func projections<Target: ProjectionsTarget>(of target: Target) -> Projections<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }

    /// Creates a projections interface for a predefined system projection.
    package func projections(system predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        .init(target: .init(predefined: predefined), selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}

// MARK: - Internal Projection Accessors

extension KurrentDBClient {
    /// Returns a projections interface targeting all projections.
    var anyProjection: Projections<AnyProjectionsTarget> {
        projections(of: .any)
    }

    /// Returns a projections interface for a continuous projection with the specified name.
    func continuousProjection(name: String) -> Projections<ContinuousTarget> {
        projections(of: .continuous(name: name))
    }

    /// Returns a projections interface for one-time projections.
    var oneTimeProjection: Projections<OneTimeTarget> {
        projections(of: .onetime)
    }

    /// Returns a projections interface for a transient projection with the specified name.
    func transientProjection(name: String) -> Projections<TransientTarget> {
        projections(of: .transient(name: name))
    }

    /// Returns a projections interface for a predefined system projection.
    func systemProjection(predefined: NameTarget.Predefined) -> Projections<NameTarget> {
        projections(system: predefined)
    }
}

// MARK: - Projection Lifecycle Operations

extension KurrentDBClient {
    /// Creates and executes a one-time projection that runs to completion and then stops.
    ///
    /// One-time projections are useful for ad-hoc queries, data migrations, or generating one-off
    /// reports from your event store. Unlike continuous projections, they do not persist state or
    /// continue processing new events after completing their initial run through the event stream.
    ///
    /// ## Projection Types
    ///
    /// - **One-Time**: Runs once to completion, then stops. Does not maintain state between runs.
    /// - **Continuous**: Runs continuously, processing new events as they arrive.
    /// - **Transient**: Runs in memory without persisting state, useful for temporary queries.
    ///
    /// ## Query Language
    ///
    /// Projections use JavaScript-based query syntax with built-in functions:
    /// - `fromAll()` - Process all events from all streams
    /// - `fromCategory(category)` - Process events from streams in a category
    /// - `fromStream(streamName)` - Process events from a specific stream
    /// - `when()` - Define event handlers
    /// - `$init()` - Initialize projection state
    ///
    /// ## Use Cases
    ///
    /// - Generating one-off reports from historical events
    /// - Data migration tasks
    /// - Ad-hoc queries against the event store
    /// - Testing projection logic before creating continuous projections
    /// - Extracting specific data subsets
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = """
    /// fromAll()
    ///     .when({
    ///         $init: function() {
    ///             return { count: 0 };
    ///         },
    ///         OrderCreated: function(s, e) {
    ///             s.count += 1;
    ///         }
    ///     });
    /// """
    ///
    /// try await client.createOneTimeProjection(query: query)
    /// ```
    ///
    /// - Parameter query: JavaScript-based projection query defining the event processing logic.
    ///   Must include event source specification (`fromAll()`, `fromCategory()`, etc.) and
    ///   event handlers via `when()`.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.invalidArgument` if the query syntax is invalid.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: One-time projections execute immediately and do not appear in the projections list
    ///   after completion. Use `getProjectionState()` during execution to monitor progress.
    ///
    /// - Warning: Complex queries over large event stores can be resource-intensive. Test queries
    ///   with smaller datasets before running against production data.
    ///
    /// - SeeAlso: `createContinuousProjection(name:query:configure:)`, `createTransientProjection(name:query:)`
    public func createOneTimeProjection(query: String) async throws {
        try await projections(of: .onetime).create(query: query)
    }
    
    /// Creates a continuous projection that processes events in real-time as they are appended.
    ///
    /// Continuous projections are the most common projection type in event-sourced systems. They
    /// maintain persistent state, automatically track their position in the event stream, and
    /// continue processing new events as they arrive. Use continuous projections to build read
    /// models, maintain denormalized views, or trigger side effects based on domain events.
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure allows customization of projection behavior:
    /// - **Track Emitted Streams**: Whether to track streams emitted by this projection
    /// - **Emit Enabled**: Control whether the projection can emit new events
    /// - **Checkpoint Settings**: Configure checkpoint frequency and thresholds
    ///
    /// ## Projection State
    ///
    /// Continuous projections persist their state and checkpoint position to disk, allowing them to:
    /// - Resume from the last checkpoint after server restarts
    /// - Be reset to replay all events from the beginning
    /// - Maintain consistent read models across cluster nodes
    ///
    /// ## Use Cases
    ///
    /// - Building read models for CQRS query handlers
    /// - Maintaining denormalized views for performance
    /// - Creating category or event-type indexes
    /// - Aggregating data across multiple streams
    /// - Triggering notifications or external system integrations
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = """
    /// fromCategory('orders')
    ///     .when({
    ///         $init: function() {
    ///             return {
    ///                 totalOrders: 0,
    ///                 totalRevenue: 0
    ///             };
    ///         },
    ///         OrderCreated: function(s, e) {
    ///             s.totalOrders += 1;
    ///             s.totalRevenue += e.body.amount;
    ///         }
    ///     });
    /// """
    ///
    /// try await client.createContinuousProjection(
    ///     name: "order-statistics",
    ///     query: query
    /// ) {
    ///     $0.trackEmittedStreams(true)
    ///       .emitEnabled(true)
    /// }
    ///
    /// // Enable the projection to start processing
    /// try await client.enableProjection(name: "order-statistics")
    /// ```
    ///
    /// - Parameters:
    ///   - name: Unique identifier for the projection. Must be unique across all continuous
    ///     projections in the cluster. Use descriptive names that indicate the projection's purpose.
    ///   - query: JavaScript-based projection query. Must include event source specification and
    ///     event handlers. Can use `emit()` to write derived events to new streams if emit is enabled.
    ///   - configure: Optional closure to configure projection creation options. Defaults to standard
    ///     settings with emit disabled and no stream tracking.
    ///
    /// - Throws: `KurrentError.alreadyExists` if a projection with this name already exists.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.invalidArgument` if the query syntax is invalid or name is empty.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: Newly created continuous projections start in a disabled state. Call
    ///   `enableProjection(name:)` to begin event processing. This allows you to verify
    ///   the projection configuration before it starts consuming resources.
    ///
    /// - Warning: Projections with `emitEnabled(true)` can write events back to the event store,
    ///   potentially creating feedback loops. Carefully design emit logic to avoid infinite recursion.
    ///
    /// - SeeAlso: `enableProjection(name:)`, `updateProjection(name:query:configure:)`,
    ///   `getProjectionState(of:name:configure:)`
    public func createContinuousProjection(name: String, query: String, configure: @Sendable (Projections<ContinuousTarget>.ContinuousCreate.Options) -> Projections<ContinuousTarget>.ContinuousCreate.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(of: .continuous(name: name)).create(query: query, options: options)
    }
    
    /// Creates a transient projection that runs in memory without persisting state to disk.
    ///
    /// Transient projections are useful for temporary queries, development testing, or scenarios where
    /// projection state does not need to survive server restarts. They process events in real-time like
    /// continuous projections but keep all state in memory, making them faster but ephemeral.
    ///
    /// ## Characteristics
    ///
    /// - **In-Memory State**: All projection state is kept in RAM, not persisted to disk
    /// - **No Checkpoints**: Position is not saved; restarts cause the projection to replay from the beginning
    /// - **Fast Performance**: No disk I/O overhead for state persistence
    /// - **Temporary**: State is lost when the projection stops or server restarts
    ///
    /// ## Use Cases
    ///
    /// - Development and testing of projection queries before creating continuous versions
    /// - Temporary data analysis during troubleshooting
    /// - Short-lived aggregations that don't require persistence
    /// - Performance testing projection logic without disk I/O overhead
    /// - Cache-like read models that can be rebuilt quickly
    ///
    /// ## Performance Considerations
    ///
    /// Transient projections consume server memory proportional to their state size. For projections
    /// that accumulate large amounts of state, consider using continuous projections instead to avoid
    /// memory pressure on the server.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let query = """
    /// fromStream('sensor-readings')
    ///     .when({
    ///         $init: function() {
    ///             return {
    ///                 last5Readings: []
    ///             };
    ///         },
    ///         ReadingRecorded: function(s, e) {
    ///             s.last5Readings.push(e.body.value);
    ///             if (s.last5Readings.length > 5) {
    ///                 s.last5Readings.shift();
    ///             }
    ///         }
    ///     });
    /// """
    ///
    /// try await client.createTransientProjection(
    ///     name: "recent-readings",
    ///     query: query
    /// )
    ///
    /// // Query the transient projection state
    /// let state = try await client.getProjectionState(
    ///     of: [String: [Double]].self,
    ///     name: "recent-readings"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - name: Unique identifier for the transient projection. Must be unique across all
    ///     projections in the cluster.
    ///   - query: JavaScript-based projection query defining the event processing logic and
    ///     in-memory state structure.
    ///
    /// - Throws: `KurrentError.alreadyExists` if a projection with this name already exists.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.invalidArgument` if the query syntax is invalid or name is empty.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: Transient projections start automatically upon creation, unlike continuous
    ///   projections which require explicit enablement.
    ///
    /// - Warning: Transient projection state is completely lost on server restart or if the
    ///   projection is deleted. Do not rely on transient projections for critical business data.
    ///
    /// - SeeAlso: `createContinuousProjection(name:query:configure:)`, `deleteProjection(name:configure:)`
    public func createTransientProjection(name: String, query: String) async throws {
        try await projections(of: .transient(name: name)).create(query: query)
    }

    /// Updates an existing projection's query definition and optionally emits a checkpoint.
    ///
    /// Updating a projection modifies its event processing logic without losing its current position
    /// in the event stream. This allows you to refine projection behavior, fix bugs, or add new event
    /// handlers while maintaining continuity. The projection will continue processing from its last
    /// checkpoint using the new query definition.
    ///
    /// ## Update Behavior
    ///
    /// When a projection is updated:
    /// - The new query replaces the old one immediately
    /// - The projection's checkpoint position is preserved
    /// - If emit is enabled, existing emitted streams remain unless explicitly deleted
    /// - The projection continues running if it was enabled
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure supports:
    /// - **Emit Checkpoint**: Force the projection to write its current position immediately after update
    /// - **Tracking Options**: Modify how emitted streams are tracked (if applicable)
    ///
    /// ## State Migration
    ///
    /// If the new query changes the state structure, consider:
    /// 1. Resetting the projection to replay all events with the new schema
    /// 2. Designing the query to migrate existing state in `$init()`
    /// 3. Creating a new projection and deprecating the old one
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Original query only counted orders
    /// let originalQuery = """
    /// fromCategory('orders')
    ///     .when({
    ///         $init: function() { return { count: 0 }; },
    ///         OrderCreated: function(s, e) { s.count += 1; }
    ///     });
    /// """
    ///
    /// // Updated query also tracks revenue
    /// let updatedQuery = """
    /// fromCategory('orders')
    ///     .when({
    ///         $init: function() {
    ///             return { count: 0, revenue: 0 };
    ///         },
    ///         OrderCreated: function(s, e) {
    ///             s.count += 1;
    ///             s.revenue += e.body.amount || 0;
    ///         }
    ///     });
    /// """
    ///
    /// try await client.updateProjection(
    ///     name: "order-statistics",
    ///     query: updatedQuery
    /// ) {
    ///     $0.emitEnabled(true)
    /// }
    ///
    /// // Consider resetting to apply new logic to historical events
    /// try await client.resetProjection(name: "order-statistics")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the projection to update. Must be an existing continuous or
    ///     transient projection.
    ///   - query: New JavaScript-based projection query. Must include complete projection logic
    ///     including event source and handlers.
    ///   - configure: Optional closure to configure update options. Use this to control checkpoint
    ///     emission and tracking behavior.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.invalidArgument` if the query syntax is invalid.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: System projections (prefixed with `$`) cannot be updated as they are managed by
    ///   the KurrentDB server itself.
    ///
    /// - Warning: Updating a projection while it is running may cause temporary inconsistencies
    ///   as the new query is applied. For production systems, consider disabling the projection,
    ///   updating it, resetting if needed, and then re-enabling.
    ///
    /// - SeeAlso: `resetProjection(name:)`, `disableProjection(name:)`, `enableProjection(name:)`
    public func updateProjection(name: String, query: String, configure: @Sendable (Projections<NameTarget>.Update.Options) -> Projections<NameTarget>.Update.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(of: NameTarget(name: name)).update(query: query, options: options)
    }

    /// Enables a projection to begin processing events from its last checkpoint position.
    ///
    /// Enabling a projection starts or resumes event processing. Newly created continuous projections
    /// begin in a disabled state and require explicit enablement. When enabled, the projection resumes
    /// from its last checkpoint position, processes any events it missed while disabled, and continues
    /// tracking new events in real-time.
    ///
    /// ## Projection Lifecycle
    ///
    /// 1. **Created**: Projection exists but is not processing events
    /// 2. **Enabled**: Projection processes events and maintains state
    /// 3. **Disabled**: Projection pauses but retains its checkpoint
    /// 4. **Reset**: Projection checkpoint is cleared, ready to replay from the beginning
    ///
    /// ## Use Cases
    ///
    /// - Starting a newly created continuous projection
    /// - Resuming a projection after maintenance or updates
    /// - Re-enabling a projection after fixing query bugs
    /// - Starting projections as part of deployment automation
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Create projection (starts disabled)
    /// try await client.createContinuousProjection(
    ///     name: "user-analytics",
    ///     query: query
    /// )
    ///
    /// // Enable to start processing
    /// try await client.enableProjection(name: "user-analytics")
    ///
    /// // Monitor processing progress
    /// let detail = try await client.getProjectionDetail(name: "user-analytics")
    /// print("Progress: \(detail.progress)%")
    /// ```
    ///
    /// - Parameter name: The name of the projection to enable. Must be an existing continuous
    ///   or transient projection in a disabled state.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: Enabling an already-enabled projection is a no-op and will not throw an error.
    ///
    /// - SeeAlso: `disableProjection(name:)`, `createContinuousProjection(name:query:configure:)`
    public func enableProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).enable()
    }

    /// Disables a projection, pausing event processing while preserving its checkpoint.
    ///
    /// Disabling a projection stops it from processing events but maintains its current position
    /// in the event stream. The projection's state and checkpoint are preserved, allowing it to
    /// resume from exactly where it stopped when re-enabled. This is useful for temporarily pausing
    /// projections during maintenance, updates, or troubleshooting.
    ///
    /// ## Checkpoint Behavior
    ///
    /// When disabled:
    /// - A checkpoint is written immediately to persist the current position
    /// - All projection state is saved to disk (for continuous projections)
    /// - Event processing stops gracefully
    /// - The projection remains visible in management interfaces
    ///
    /// ## Use Cases
    ///
    /// - Pausing projections during system maintenance
    /// - Temporarily stopping resource-intensive projections
    /// - Preparing a projection for updates or query changes
    /// - Troubleshooting projection behavior without losing state
    /// - Managing server resource utilization
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Disable projection for maintenance
    /// try await client.disableProjection(name: "expensive-analytics")
    ///
    /// // Perform maintenance operations
    /// try await client.updateProjection(
    ///     name: "expensive-analytics",
    ///     query: optimizedQuery
    /// )
    ///
    /// // Re-enable to resume processing
    /// try await client.enableProjection(name: "expensive-analytics")
    /// ```
    ///
    /// - Parameter name: The name of the projection to disable. Must be an existing continuous
    ///   or transient projection.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: Disabling writes a checkpoint to ensure no events are lost. The projection will
    ///   resume from this checkpoint when re-enabled.
    ///
    /// - Warning: Disabling a projection causes its read model to become stale as new events
    ///   are not processed. Re-enable promptly to maintain data freshness.
    ///
    /// - SeeAlso: `enableProjection(name:)`, `abortProjection(name:)`, `updateProjection(name:query:configure:)`
    public func disableProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).disable()
    }

    /// Aborts a running projection immediately without writing a checkpoint.
    ///
    /// Aborting a projection stops event processing instantly without saving the current position
    /// to disk. Unlike `disableProjection`, which writes a checkpoint before stopping, abort is
    /// designed for emergency situations where you need to halt a misbehaving projection immediately.
    ///
    /// ## Abort vs Disable
    ///
    /// - **Abort**: Stops immediately, no checkpoint written, position may be lost
    /// - **Disable**: Stops gracefully, checkpoint written, position preserved
    ///
    /// ## Use Cases
    ///
    /// - Emergency shutdown of projections consuming excessive resources
    /// - Stopping projections with infinite loops or runaway queries
    /// - Halting projections that are causing system instability
    /// - Quickly stopping projections during critical incidents
    ///
    /// ## Recovery
    ///
    /// After aborting, the projection may resume from an earlier checkpoint when re-enabled,
    /// potentially reprocessing some events. For a clean restart, use `resetProjection()` after
    /// aborting to replay from the beginning.
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Abort a projection causing problems
    /// try await client.abortProjection(name: "problematic-projection")
    ///
    /// // Fix the query
    /// try await client.updateProjection(
    ///     name: "problematic-projection",
    ///     query: fixedQuery
    /// )
    ///
    /// // Reset and restart from the beginning
    /// try await client.resetProjection(name: "problematic-projection")
    /// try await client.enableProjection(name: "problematic-projection")
    /// ```
    ///
    /// - Parameter name: The name of the projection to abort. Must be an existing continuous
    ///   or transient projection.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Warning: Aborting without a checkpoint may cause the projection to reprocess events
    ///   from the last successful checkpoint, potentially causing duplicate processing or
    ///   inconsistent state. Use `disableProjection()` for graceful shutdown instead.
    ///
    /// - SeeAlso: `disableProjection(name:)`, `resetProjection(name:)`
    public func abortProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).abort()
    }

    /// Deletes a projection and optionally removes all streams it emitted.
    ///
    /// Deleting a projection permanently removes it from the system, including its query definition,
    /// state, and checkpoint position. For projections configured with `emitEnabled(true)`, you can
    /// optionally delete all streams created by the projection's `emit()` calls.
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure supports:
    /// - **Delete Emitted Streams**: Remove all streams created by this projection's `emit()` calls
    /// - **Delete State Stream**: Remove the projection's internal state stream
    /// - **Delete Checkpoint Stream**: Remove the projection's checkpoint tracking stream
    ///
    /// ## Deletion Scope
    ///
    /// When a projection is deleted:
    /// - Query definition is removed
    /// - Projection state is cleared
    /// - Checkpoint position is lost
    /// - Optionally, emitted streams are deleted based on configuration
    ///
    /// ## Use Cases
    ///
    /// - Removing obsolete projections no longer needed
    /// - Cleaning up failed projection experiments
    /// - Decommissioning projections replaced by newer versions
    /// - Freeing up system resources
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Delete projection and its emitted streams
    /// try await client.deleteProjection(name: "old-analytics") {
    ///     $0.deleteEmittedStreams()
    /// }
    ///
    /// // Delete projection but keep emitted streams
    /// try await client.deleteProjection(name: "data-migrator")
    /// ```
    ///
    /// - Parameters:
    ///   - name: The name of the projection to delete. Can be continuous or transient.
    ///   - configure: Optional closure to configure deletion behavior, particularly whether to
    ///     delete emitted streams. Defaults to preserving emitted streams.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Warning: Deletion is permanent and cannot be undone. The projection must be recreated
    ///   from scratch if needed again. Back up projection queries before deleting.
    ///
    /// - Warning: Deleting emitted streams removes all events written by the projection's `emit()`
    ///   calls. Only use this option if you're certain the emitted data is no longer needed.
    ///
    /// - SeeAlso: `disableProjection(name:)`, `resetProjection(name:)`
    public func deleteProjection(name: String, configure: @Sendable (Projections<NameTarget>.Delete.Options) -> Projections<NameTarget>.Delete.Options = { $0 }) async throws {
        let options = configure(.init())
        try await projections(of: NameTarget(name: name)).delete(options: options)
    }

    /// Resets a projection to its initial state, clearing all state and checkpoint data.
    ///
    /// Resetting a projection clears its accumulated state and checkpoint position, causing it to
    /// replay all events from the beginning of its source streams when next enabled. This is useful
    /// for applying query updates to historical events, recovering from corrupt state, or rebuilding
    /// read models after schema changes.
    ///
    /// ## Reset Behavior
    ///
    /// When a projection is reset:
    /// 1. The projection is automatically disabled if running
    /// 2. All accumulated state is cleared
    /// 3. The checkpoint position is reset to the stream beginning
    /// 4. The projection remains disabled until explicitly re-enabled
    /// 5. Upon re-enabling, all events are reprocessed from the start
    ///
    /// ## Use Cases
    ///
    /// - Applying updated projection queries to historical events
    /// - Recovering from corrupt projection state
    /// - Rebuilding read models after schema or business logic changes
    /// - Testing projection behavior against full event history
    /// - Fixing projections that skipped events due to bugs
    ///
    /// ## Performance Considerations
    ///
    /// Resetting a projection on a large event store will cause significant processing load as all
    /// events are replayed. For production systems:
    /// - Schedule resets during maintenance windows
    /// - Monitor server resources during replay
    /// - Consider using transient projections to test queries before resetting continuous ones
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Disable projection before making changes
    /// try await client.disableProjection(name: "user-statistics")
    ///
    /// // Update query with new logic
    /// try await client.updateProjection(
    ///     name: "user-statistics",
    ///     query: updatedQuery
    /// )
    ///
    /// // Reset to apply new query to all historical events
    /// try await client.resetProjection(name: "user-statistics")
    ///
    /// // Re-enable to start processing
    /// try await client.enableProjection(name: "user-statistics")
    ///
    /// // Monitor replay progress
    /// let detail = try await client.getProjectionDetail(name: "user-statistics")
    /// print("Rebuild progress: \(detail.progress)%")
    /// ```
    ///
    /// - Parameter name: The name of the projection to reset. Must be an existing continuous
    ///   or transient projection.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection management permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: System projections (like `$by_category`) cannot be reset as they are managed
    ///   by the server.
    ///
    /// - Warning: Resetting a projection serving live queries will cause read model staleness
    ///   until the replay completes. Plan for application degradation during the reset period.
    ///
    /// - SeeAlso: `updateProjection(name:query:configure:)`, `enableProjection(name:)`,
    ///   `getProjectionDetail(name:)`
    public func resetProjection(name: String) async throws {
        try await projections(of: NameTarget(name: name)).reset()
    }

    /// Retrieves the result output of a projection, decoded to the specified Swift type.
    ///
    /// Projection results represent the final output of a projection's processing, typically used
    /// when projections emit derived events or generate computed data. Unlike projection state,
    /// which represents internal working data, the result is the projection's public output intended
    /// for consumption by other systems or queries.
    ///
    /// ## Result vs State
    ///
    /// - **Result**: The projection's final output, often emitted as events or published data
    /// - **State**: The projection's internal working memory, used for event processing logic
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure allows:
    /// - **Partition Selection**: Retrieve results from specific projection partitions
    /// - **Formatting Options**: Control JSON serialization format
    ///
    /// ## Type Safety
    ///
    /// Results are decoded using Swift's `Codable` protocol. Ensure your type matches the projection's
    /// result structure, or use flexible types like `[String: Any]` or `AnyCodable` for dynamic schemas.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct OrderStatistics: Codable, Sendable {
    ///     let totalOrders: Int
    ///     let totalRevenue: Double
    ///     let averageOrderValue: Double
    /// }
    ///
    /// let query = """
    /// fromCategory('orders')
    ///     .when({
    ///         $init: function() {
    ///             return { count: 0, revenue: 0 };
    ///         },
    ///         OrderCreated: function(s, e) {
    ///             s.count += 1;
    ///             s.revenue += e.body.amount;
    ///         }
    ///     })
    ///     .outputState();
    /// """
    ///
    /// let stats = try await client.getProjectionResult(
    ///     of: OrderStatistics.self,
    ///     name: "order-statistics"
    /// )
    ///
    /// if let stats = stats {
    ///     print("Total orders: \(stats.totalOrders)")
    ///     print("Average: $\(stats.averageOrderValue)")
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - of: The Swift type to decode the result into. Must conform to `Decodable` and `Sendable`.
    ///     Type inference typically allows omitting this parameter.
    ///   - name: The name of the projection to query.
    ///   - configure: Optional closure to configure result retrieval options, such as partition selection.
    ///
    /// - Returns: The decoded projection result, or `nil` if the projection has not produced results yet
    ///   or if the result is empty.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.decodingError` if the result cannot be decoded to the specified type.
    ///   `KurrentError.accessDenied` if the user lacks projection read permissions.
    ///
    /// - Note: Not all projections produce results. Ensure your projection query includes result output
    ///   logic (e.g., `outputState()` or `emit()`) before expecting results.
    ///
    /// - SeeAlso: `getProjectionState(of:name:configure:)`, `getProjectionDetail(name:)`
    public func getProjectionResult<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<NameTarget>.Result.Options) -> Projections<NameTarget>.Result.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(of: NameTarget(name: name)).result(of: T.self, options: options)
    }

    /// Retrieves the current internal state of a projection, decoded to the specified Swift type.
    ///
    /// Projection state represents the working memory maintained by the projection's event handlers.
    /// This is the data structure defined in your projection's `$init()` function and modified by
    /// event processing logic. Querying state is useful for debugging, monitoring, or building
    /// read models directly from projection state.
    ///
    /// ## State Structure
    ///
    /// The state structure is defined by your projection query's `$init()` function and modified
    /// by event handlers:
    ///
    /// ```javascript
    /// $init: function() {
    ///     return {
    ///         totalOrders: 0,
    ///         customerCount: 0,
    ///         activeProducts: {}
    ///     };
    /// }
    /// ```
    ///
    /// ## Configuration Options
    ///
    /// The `configure` closure supports:
    /// - **Partition Selection**: Query specific projection partitions
    /// - **Formatting Options**: Control JSON serialization and formatting
    ///
    /// ## Type Safety
    ///
    /// Use Swift's `Codable` protocol for type-safe state decoding. For flexible schemas, consider:
    /// - `[String: Any]` for dictionaries
    /// - `AnyCodable` for dynamic types
    /// - Custom `Decodable` implementations with flexible member access
    ///
    /// ## Use Cases
    ///
    /// - Building CQRS read models from projection state
    /// - Monitoring projection progress and health
    /// - Debugging projection logic
    /// - Extracting computed aggregates for reporting
    /// - Verifying projection correctness in tests
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct InventoryState: Codable, Sendable {
    ///     let itemsInStock: [String: Int]
    ///     let lowStockAlerts: [String]
    ///     let lastUpdated: String
    /// }
    ///
    /// let state = try await client.getProjectionState(
    ///     of: InventoryState.self,
    ///     name: "inventory-tracking"
    /// )
    ///
    /// if let inventory = state {
    ///     for alert in inventory.lowStockAlerts {
    ///         print("Low stock: \(alert)")
    ///     }
    /// }
    ///
    /// // Use dictionary for dynamic state
    /// let dynamicState = try await client.getProjectionState(
    ///     of: [String: AnyCodable].self,
    ///     name: "flexible-projection"
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - of: The Swift type to decode the state into. Must conform to `Decodable` and `Sendable`.
    ///     Type inference typically allows omitting this parameter.
    ///   - name: The name of the projection to query.
    ///   - configure: Optional closure to configure state retrieval options.
    ///
    /// - Returns: The decoded projection state, or `nil` if the projection has not accumulated
    ///   any state yet or if the state is empty.
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.decodingError` if the state cannot be decoded to the specified type.
    ///   `KurrentError.accessDenied` if the user lacks projection read permissions.
    ///
    /// - Note: Projection state updates continuously as events are processed. The returned state
    ///   represents a snapshot at query time and may be outdated immediately.
    ///
    /// - SeeAlso: `getProjectionResult(of:name:configure:)`, `getProjectionDetail(name:)`
    public func getProjectionState<T: Decodable & Sendable>(of _: T.Type = T.self, name: String, configure: @Sendable (Projections<NameTarget>.State.Options) -> Projections<NameTarget>.State.Options = { $0 }) async throws -> T? {
        let options = configure(.init())
        return try await projections(of: NameTarget(name: name)).state(of: T.self, options: options)
    }

    /// Retrieves comprehensive statistics and metadata for a specific projection.
    ///
    /// Projection details provide complete operational information including processing progress,
    /// performance metrics, checkpoint positions, and configuration settings. This is essential
    /// for monitoring projection health, debugging issues, and understanding projection behavior
    /// in production systems.
    ///
    /// ## Returned Information
    ///
    /// The statistics detail includes:
    /// - **Name and Mode**: Projection identifier and type (continuous, transient, one-time)
    /// - **Status**: Current state (Running, Stopped, Faulted, etc.)
    /// - **Progress**: Percentage of events processed
    /// - **Checkpoint Position**: Last persisted position in the event stream
    /// - **Events Processed**: Total count of events handled
    /// - **Processing Rate**: Events per second throughput
    /// - **Write Position**: Current position being processed
    /// - **Core Processing Time**: CPU time spent in event handlers
    /// - **State**: Projection state information
    ///
    /// ## Use Cases
    ///
    /// - Monitoring projection processing progress
    /// - Diagnosing performance bottlenecks
    /// - Verifying projection health in production
    /// - Building projection management dashboards
    /// - Troubleshooting failed or stalled projections
    /// - Capacity planning based on processing rates
    ///
    /// ## Example
    ///
    /// ```swift
    /// let detail = try await client.getProjectionDetail(name: "order-analytics")
    ///
    /// if let stats = detail {
    ///     print("Status: \(stats.status)")
    ///     print("Progress: \(stats.progress)%")
    ///     print("Events processed: \(stats.eventsProcessed)")
    ///     print("Processing rate: \(stats.eventsPerSecond) events/sec")
    ///
    ///     // Check if projection is healthy
    ///     if stats.status == "Faulted" {
    ///         print("ERROR: Projection has faulted!")
    ///         print("Last error: \(stats.stateReason)")
    ///     }
    ///
    ///     // Monitor replay progress after reset
    ///     if stats.progress < 100 {
    ///         print("Rebuilding: \(stats.progress)% complete")
    ///     }
    /// }
    /// ```
    ///
    /// - Parameter name: The name of the projection to query.
    ///
    /// - Returns: Detailed statistics for the projection, or `nil` if the projection exists but
    ///   has not generated statistics yet (rare).
    ///
    /// - Throws: `KurrentError.notFound` if no projection exists with the specified name.
    ///   `KurrentError.accessDenied` if the user lacks projection read permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: Statistics are generated periodically by the projection subsystem. Very new projections
    ///   may return `nil` if statistics have not been calculated yet.
    ///
    /// - SeeAlso: `listAllProjections(mode:)`, `getProjectionState(of:name:configure:)`
    public func getProjectionDetail(name: String) async throws -> Projections<NameTarget>.Statistics.Detail? {
        try await projections(of: NameTarget(name: name)).detail()
    }

    /// Lists all projections of a specific mode with their detailed statistics.
    ///
    /// Retrieves comprehensive information about all projections matching the specified mode
    /// (continuous, transient, or one-time). This is useful for management dashboards, health
    /// monitoring, and discovering available projections in the system.
    ///
    /// ## Projection Modes
    ///
    /// Filter projections by mode:
    /// - **Continuous**: Long-running projections that persist state and process new events continuously
    /// - **Transient**: In-memory projections without persistent state
    /// - **OneTime**: Ad-hoc projections that run once and stop
    /// - **All**: Returns projections of all modes
    ///
    /// ## Statistics Information
    ///
    /// Each projection in the list includes:
    /// - Name and mode
    /// - Current status (Running, Stopped, Faulted)
    /// - Processing progress percentage
    /// - Events processed count
    /// - Checkpoint positions
    /// - Performance metrics
    ///
    /// ## Use Cases
    ///
    /// - Building projection management dashboards
    /// - Monitoring overall projection health
    /// - Discovering available projections
    /// - Auditing projection configuration
    /// - Capacity planning and resource allocation
    /// - Detecting failed or stalled projections
    ///
    /// ## Example
    ///
    /// ```swift
    /// // List all continuous projections
    /// let continuousProjections = try await client.listAllProjections(
    ///     mode: Projection.Mode.continuous
    /// )
    ///
    /// for projection in continuousProjections {
    ///     print("\(projection.name): \(projection.status)")
    ///
    ///     if projection.status == "Faulted" {
    ///         print("  ERROR: \(projection.stateReason)")
    ///     } else {
    ///         print("  Progress: \(projection.progress)%")
    ///         print("  Rate: \(projection.eventsPerSecond) events/sec")
    ///     }
    /// }
    ///
    /// // Find slow projections
    /// let slowProjections = continuousProjections.filter {
    ///     $0.progress < 100 && $0.eventsPerSecond < 100
    /// }
    ///
    /// // List all projection types
    /// let allProjections = try await client.listAllProjections(
    ///     mode: Projection.Mode.all
    /// )
    /// print("Total projections: \(allProjections.count)")
    /// ```
    ///
    /// - Parameter mode: The projection mode to filter by. Use specific modes to narrow results
    ///   or `.all` to retrieve every projection in the system.
    ///
    /// - Returns: An array of detailed statistics for all matching projections. Returns an empty
    ///   array if no projections match the mode filter.
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks projection read permissions.
    ///   `KurrentError.unavailable` if the projection subsystem is not running.
    ///
    /// - Note: The list includes both user-defined projections and system projections (prefixed
    ///   with `$`) such as `$by_category` and `$by_event_type`.
    ///
    /// - SeeAlso: `getProjectionDetail(name:)`, `Projection.Mode`
    public func listAllProjections<Mode: ProjectionMode>(mode: Mode) async throws -> [Projections<AnyProjectionsTarget>.Statistics.Detail] {
        try await projections().list(for: mode)
    }

    /// Restarts the entire projection subsystem across the cluster.
    ///
    /// Restarting the projection subsystem stops all running projections, clears in-memory state,
    /// and reinitializes the projection manager. All projections are then restarted from their
    /// last checkpoints. This is a disruptive operation intended for recovery from projection
    /// subsystem failures or after configuration changes requiring a full restart.
    ///
    /// ## Restart Process
    ///
    /// During restart:
    /// 1. All running projections are stopped
    /// 2. Projection subsystem state is cleared
    /// 3. Projection manager reinitializes
    /// 4. Enabled projections restart from their last checkpoints
    /// 5. Projection statistics reset and rebuild
    ///
    /// ## Impact
    ///
    /// - **Read Models**: Temporarily unavailable during restart
    /// - **Processing**: All projections stop and resume, causing brief lag
    /// - **Checkpoints**: Preserved; projections resume from last saved position
    /// - **In-Flight Events**: May be reprocessed if not checkpointed
    ///
    /// ## Use Cases
    ///
    /// - Recovering from projection subsystem failures
    /// - Applying projection manager configuration changes
    /// - Clearing projection subsystem memory after resource leaks
    /// - Forcing reload of projection definitions
    /// - Troubleshooting projection coordination issues
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Restart projection subsystem after configuration change
    /// try await client.restartProjectionSubsystem()
    ///
    /// // Wait for projections to come back online
    /// try await Task.sleep(for: .seconds(5))
    ///
    /// // Verify projections restarted successfully
    /// let projections = try await client.listAllProjections(
    ///     mode: Projection.Mode.continuous
    /// )
    ///
    /// for projection in projections {
    ///     let detail = try await client.getProjectionDetail(name: projection.name)
    ///     guard detail?.status == "Running" else {
    ///         print("WARNING: \(projection.name) not running after restart")
    ///         continue
    ///     }
    /// }
    /// ```
    ///
    /// - Throws: `KurrentError.accessDenied` if the user lacks administrative permissions.
    ///   `KurrentError.unavailable` if the projection subsystem cannot be restarted.
    ///
    /// - Warning: This is a cluster-wide disruptive operation that affects all projections
    ///   simultaneously. All read models become temporarily unavailable. Only use during
    ///   maintenance windows or when recovering from subsystem failures.
    ///
    /// - Warning: Requires administrative permissions. This operation should be restricted
    ///   to operators and automated recovery systems.
    ///
    /// - SeeAlso: `listAllProjections(mode:)`, `enableProjection(name:)`
    public func restartProjectionSubsystem() async throws(KurrentError) {
        let usecase = Projections<AnyProjectionsTarget>.RestartSubsystem()
        _ = try await usecase.perform(selector: selector, callOptions: defaultCallOptions)
    }
}
