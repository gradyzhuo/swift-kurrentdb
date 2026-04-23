//
//  KurrentDBClient+Streams.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/5/23.
//

extension KurrentDBClient {
    /// Returns a ``Streams`` instance scoped to the given target.
    ///
    /// ```swift
    /// let orders = client.streams(of: .specified("orders"))
    /// try await orders.append(events: events)
    ///
    /// for try await response in try await client.streams(of: .all).read() { }
    /// ```
    ///
    /// - Parameter target: The stream target. Use static factories such as `.specified(_:)`, `.all`, or `.multiple`.
    /// - Returns: A ``Streams`` instance configured for the given target.
    public func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target> {
        .init(target: target, selector: selector, callOptions: defaultCallOptions, eventLoopGroup: eventLoopGroup)
    }
}

extension KurrentDBClient {
    /// Returns a ``Streams`` instance for a named stream.
    ///
    /// - Parameter name: Name of the stream to access.
    /// - Returns: A `Streams<SpecifiedStream>` configured for the named stream.
    public func streams(specified name: String) -> Streams<SpecifiedStream> {
        streams(of: .specified(name))
    }

    /// Streams interface for batch append operations across multiple streams (requires KurrentDB 25.1+).
    public var multiStreams: Streams<MultiStreamsTarget> {
        streams(of: .multiple)
    }

    /// Streams interface for the global `$all` event log.
    public var allStreams: Streams<AllStreamsTarget> {
        streams(of: .all)
    }
}
