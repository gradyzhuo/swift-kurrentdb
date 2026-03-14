//
//  KurrentDBClient+Streams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

extension KurrentDBClient {
    /// Creates a type-safe streams interface for the specified target.
    ///
    /// This method returns a `Streams` instance configured for operations on a specific
    /// stream, the `$all` stream, or multiple streams simultaneously. The returned instance
    /// inherits the client's node selector, call options, and event loop group for consistent
    /// behavior across all stream operations.
    ///
    /// ## Target Types
    ///
    /// - `SpecifiedStream`: Operations on a single named stream
    /// - `AllStreamsTarget`: Operations on the `$all` stream (global event log)
    /// - `MultiStreamsTarget`: Batch operations across multiple streams
    /// - `ProjectionStream`: Operations on projection-generated streams
    ///
    /// ## Example
    ///
    /// ```swift
    /// // Access a specific stream
    /// let ordersStream = client.streams(of: .specified("orders"))
    /// try await ordersStream.append(events: events)
    ///
    /// // Access the $all stream
    /// let allStream = client.streams(of: .all)
    /// let events = try await allStream.read()
    /// ```
    ///
    /// - Parameter target: The stream target defining the scope of operations. Use static
    ///   factory methods like `.specified(_:)`, `.all`, or `.multiple` to create targets.
    ///
    /// - Returns: A configured `Streams<Target>` instance ready for stream operations.
    ///
    /// - Note: This method creates a new streams instance on each call. For repeated operations
    ///   on the same stream, consider storing the returned instance to avoid recreation overhead.
    ///
    /// - SeeAlso: `StreamsTarget`, `Streams`, `SpecifiedStream`, `AllStreamsTarget`
    public func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}

extension KurrentDBClient {
    /// Creates a streams interface for a specific stream by name.
    ///
    /// - Parameter name: The name of the stream to access.
    ///
    /// - Returns: A `Streams<SpecifiedStream>` instance configured for the named stream.
    ///
    /// - SeeAlso: `streams(of:)`, `SpecifiedStream`
    public func streams(specified name: String) -> Streams<SpecifiedStream> {
        streams(of: .specified(name))
    }

    /// Accesses the multi-streams interface for batch operations across multiple streams.
    ///
    /// - Returns: A `Streams<MultiStreamsTarget>` instance for multi-stream operations.
    ///
    /// - Note: Multi-stream operations require KurrentDB server version 25.1 or later.
    ///
    /// - SeeAlso: `MultiStreamsTarget`
    public var multiStreams: Streams<MultiStreamsTarget> {
        streams(of: .multiple)
    }

    /// Accesses the `$all` stream for global event log operations.
    ///
    /// - Returns: A `Streams<AllStreamsTarget>` instance for `$all` stream operations.
    ///
    /// - Warning: Reading from `$all` can return a very large number of events. Always
    ///   use appropriate filtering and pagination when working with the global log.
    ///
    /// - SeeAlso: `AllStreamsTarget`
    public var allStreams: Streams<AllStreamsTarget> {
        streams(of: .all)
    }
}
