//
//  PersistentSubscriptions.AllStream.ReplayParked.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    /// Usecase for replaying parked (dead-letter) events on a persistent subscription for the `$all` stream.
    public struct ReplayParked: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.ReplayParked.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.ReplayParked.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.ReplayParked.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        let group: String
        let options: Options

        init(group: String, options: Options) {
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request message for replaying parked events, setting the group name and options.
        ///
        /// - Returns: A configured `UnderlyingRequest` for the replay parked operation.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = group
            }
        }

        /// Sends a replay parked request for a persistent subscription to all streams and processes the response asynchronously.
        ///
        /// - Returns: A wrapped response indicating the result of the replay operation.
        ///
        /// - Throws: An error if the gRPC call fails or the response cannot be handled.
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.replayParked(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.AllStream.ReplayParked {
    /// Configuration options for replaying parked events on a persistent subscription for the `$all` stream.
    public struct Options: CommandOptions {
        /// Controls when the replay of parked events should stop.
        public enum StopAtOption: Sendable {
            /// Stop replaying when the specified stream position is reached.
            case position(position: Int64)
            /// Replay all parked events without an upper bound.
            case noLimit
        }

        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// The stopping condition for the parked event replay.
        public var stopAt: StopAtOption

        public init() {
            stopAt = .noLimit
        }

        /// Constructs the underlying gRPC options message for replaying parked events, setting the stopping condition based on the current `stopAt` option.
        ///
        /// - Returns: An options message configured with either no limit or a specific stopping position.
        package func build() -> UnderlyingMessage {
            .with {
                $0.all = .init()
                switch stopAt {
                case .noLimit:
                    $0.noLimit = .init()
                case let .position(position):
                    $0.stopAt = position
                }
            }
        }
    }
}
