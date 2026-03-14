//
//  KurrentDBClient+Streams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

extension KurrentDBClient {
    /// Creates a type-safe streams interface for the specified target.
    ///
    /// The target determines the scope and available operations:
    /// - `.specified(_:)` — single named stream (append, read, subscribe, delete)
    /// - `.all` — global `$all` stream (read, subscribe)
    /// - `.multiple` — batch operations across multiple streams (requires server 25.1+)
    ///
    /// ```swift
    /// let orders = client.streams(of: .specified("orders"))
    /// try await orders.append(events: events)
    ///
    /// let allEvents = try await client.streams(of: .all).read()
    /// ```
    ///
    /// - Parameter target: The stream target. Use static factories like `.specified(_:)`, `.all`, or `.multiple`.
    /// - Returns: A configured ``Streams`` instance ready for stream operations.
    ///
    /// - SeeAlso: ``StreamsTarget``, ``SpecifiedStream``, ``AllStreamsTarget``, ``MultiStreamsTarget``
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
