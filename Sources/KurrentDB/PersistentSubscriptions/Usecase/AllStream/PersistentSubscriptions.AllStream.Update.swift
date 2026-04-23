//
//  PersistentSubscriptions.AllStream.Update.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/13.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    /// Usecase for updating a persistent subscription on the `$all` stream.
    public struct Update: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Update.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        /// The consumer group name for the persistent subscription being updated.
        public private(set) var group: String
        /// The updated options to apply to the persistent subscription.
        public private(set) var options: Options

        init(group: String, options: Options) {
            self.group = group
            self.options = options
        }

        /// Constructs the gRPC request message for updating a persistent subscription on all streams.
        ///
        /// - Throws: An error if building the options fails, such as when encoding the position cursor.
        ///
        /// - Returns: The configured gRPC request message for the update operation.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = group
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.AllStream.Update {
    /// Configuration options for updating a persistent subscription on the `$all` stream.
    public struct Options: CommandOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// The updated subscription settings such as consumer strategy, timeouts, and retry behaviour.
        public var settings: PersistentSubscription.UpdateSettings
        /// The new starting position in the `$all` stream, or `nil` to leave it unchanged.
        public var position: PositionCursor?

        public init() {
            settings = .init()
            position = nil
        }

        /// Constructs the underlying gRPC options message for updating a persistent subscription on all streams.
        ///
        /// The message includes the subscription settings and, if specified, the starting position (start, end, or a particular commit and prepare position).
        ///
        /// - Returns: The gRPC options message configured with the current settings and position.
        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .from(settings: settings)
                $0.all = .with {
                    if let position {
                        switch position {
                        case .start:
                            $0.start = .init()
                        case .end:
                            $0.end = .init()
                        case let .specified(commitPosition, preparePosition):
                            $0.position = .with {
                                $0.commitPosition = commitPosition
                                $0.preparePosition = preparePosition
                            }
                        }
                    }
                }
            }
        }
    }
}
