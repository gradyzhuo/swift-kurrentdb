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

/// gRPC service for interacting with KurrentDB event streams.
///
/// Obtain a `Streams` instance via ``KurrentDBClient`` factory methods. The `Target` type
/// determines which operations are available (append, read, subscribe, delete, metadata).
///
/// ```swift
/// let client = KurrentDBClient(settings: .localhost())
///
/// // Append to a named stream
/// try await client.streams(specified: "orders").append(events: [event])
///
/// // Read from $all
/// for try await response in try await client.allStreams.read() {
///     print(response)
/// }
/// ```
public final class Streams<Target: StreamsTarget>: GRPCConcreteService {
    /// The underlying client type used for gRPC communication.
    package typealias UnderlyingClient = EventStore_Client_Streams_Streams.Client<HTTP2ClientTransport.Posix>

    /// The client settings required for establishing a gRPC connection.
    internal let selector: NodeSelector

    /// The gRPC call options.
    internal let callOptions: CallOptions

    /// The event loop group handling asynchronous tasks.
    internal let eventLoopGroup: EventLoopGroup

    /// The target that defines the scope of stream operations.
    public let target: Target

    init(target: Target, selector: NodeSelector, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.target = target
        self.selector = selector
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}






