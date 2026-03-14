//
//  Streams.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/17.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

/// A generic gRPC service for handling event streams.
///
/// `Streams` enables interaction with event streams through operations such as appending, reading,
/// subscribing, deleting, and managing metadata. It is a concrete implementation of `GRPCConcreteService`.
///
/// The type parameter `Target` determines the scope of the stream:
/// - `SpecifiedStream`: A single named stream
/// - `AllStreamsTarget`: The global `$all` stream containing all events
/// - `MultiStreamsTarget`: Batch operations across multiple streams
/// - `ProjectionStream`: A projection-generated stream
///
/// ## Usage
///
/// Obtain a `Streams` instance through `KurrentDBClient`:
///
/// ```swift
/// let client = KurrentDBClient(settings: .localhost())
///
/// // Append to a specific stream
/// let stream = client.streams(specified: "orders")
/// try await stream.append(events: [event])
///
/// // Read from $all
/// let responses = try await client.allStreams.read()
/// for try await response in responses {
///     print(response)
/// }
/// ```
///
/// - Note: `Streams` instances are obtained via `KurrentDBClient` factory methods and should not be
///   constructed directly.
///
/// ### Topics
/// #### Specific Stream Operations
/// - ``setMetadata(metadata:)``
/// - ``getMetadata(cursor:)``
/// - ``append(events:options:)``
/// - ``read(cursor:options:)``
/// - ``subscribe(from:options:)``
/// - ``delete(options:)``
/// - ``tombstone(options:)``
///
/// #### Projection Stream Operations
/// - ``subscribe(from:options:)-swift.struct-8y6e8``
///
/// #### All Streams Operations
/// - ``read(cursor:options:)-6h8h2``
/// - ``subscribe(from:options:)-9gq2e``
public final class Streams<Target: StreamsTarget>: GRPCConcreteService {
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    /// The client settings required for establishing a gRPC connection.
    internal let selector: NodeSelector

    /// The gRPC call options.
    internal let callOptions: CallOptions

    /// The event loop group handling asynchronous tasks.
    internal let eventLoopGroup: EventLoopGroup

    /// The target stream, defining the scope of operations (e.g., specific stream or all streams).
    public let target: Target

    /// Initializes a `Streams` instance with a target and node selector.
    ///
    /// - Parameters:
    ///   - target: The stream target (e.g., `SpecifiedStream`, `AllStreamsTarget`, or `MultiStreamsTarget`).
    ///   - selector: The node selector used to resolve the gRPC connection endpoint.
    ///   - callOptions: The gRPC call options, defaulting to `.defaults`.
    ///   - eventLoopGroup: The event loop group, defaulting to a shared multi-threaded group.
    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}






