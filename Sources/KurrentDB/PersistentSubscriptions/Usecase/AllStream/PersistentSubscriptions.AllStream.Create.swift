//
//  PersistentSubscriptions.AllStream.Create.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    public struct Create: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Create.descriptor
            }
        }

        package static var name: String{
            get{
                "PersistentSubscriptions.\(Self.self)"
            }
        }
        
        let group: String
        let options: Options

        public init(group: String, options: Options) {
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request message for creating a persistent subscription.
        ///
        /// Builds the request based on the selected stream(s), group name, and subscription options, including cursor position and optional filters.
        ///
        /// - Returns: The constructed gRPC request message.
        /// Constructs the gRPC request message for creating a persistent subscription to all streams.
        ///
        /// - Throws: An error if building the subscription options fails.
        ///
        /// - Returns: The underlying gRPC request message with the configured group name and options.
        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.groupName = group
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.create(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.AllStream.Create {
    public struct Options: CommandOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.CreateSettings
        public private(set) var filter: SubscriptionFilter?
        public private(set) var position: PositionCursor

        public init() {
            settings = .init()
            filter = nil
            position = .end
        }

        /// Returns a copy of the options with the specified subscription filter applied.
        ///
        /// - Parameter filter: The filter to use for the subscription.
        /// - Returns: A new options instance with the filter set.
        @discardableResult
        public func filter(_ filter: SubscriptionFilter) -> Self {
            withCopy { $0.filter = filter }
        }

        /// Returns a copy of the options with the starting position for the subscription set to the specified cursor.
        ///
        /// - Parameter position: The position in the stream from which to start the subscription.
        /// - Returns: A modified copy of the options with the updated starting position.
        @discardableResult
        public func startFrom(position: PositionCursor) -> Self {
            withCopy {
                $0.position = position
            }
        }

        /// Builds the underlying gRPC message for creating a persistent subscription to all streams.
        ///
        /// Configures the subscription settings, optional filter, and starting position within the stream.
        ///
        /// - Returns: The constructed gRPC request message for creating the persistent subscription.
        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)

                if let filter {
                    $0.all.filter = .make(with: filter)
                } else {
                    $0.all.noFilter = .init()
                }

                $0.all = .with {
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
