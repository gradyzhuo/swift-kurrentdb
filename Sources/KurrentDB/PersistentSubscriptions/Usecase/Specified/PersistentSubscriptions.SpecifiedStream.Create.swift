//
//  PersistentSubscriptions.SpecifiedStream.Create.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct Create: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>
        
        package static var name: String{
            get{
                "PersistentSubscriptions.\(Self.self)"
            }
        }
        
        let streamIdentifier: StreamIdentifier
        let group: String
        let options: Options

        public init(streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request message for creating a persistent subscription.
        ///
        /// Builds the request based on the selected stream(s), group name, and subscription options, including cursor position and optional filters.
        ///
        /// - Returns: The constructed gRPC request message.
        /// Constructs the gRPC request message for creating a persistent subscription on a specified stream.
        ///
        /// - Throws: An error if building the stream identifier fails.
        /// - Returns: The fully constructed gRPC request message for the create persistent subscription operation.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
            }
        }

        /// Sends an asynchronous gRPC request to create a persistent subscription on a specified stream.
        ///
        /// - Returns: A response indicating the result of the create operation.
        ///
        /// - Throws: An error if the request fails or the response cannot be handled.
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.create(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.SpecifiedStream.Create {
    public struct Options: EventStoreOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.CreateSettings
        public private(set) var revision: RevisionCursor

        public init() {
            settings = .init()
            revision = .end
        }

        /// Returns a copy of the options with the starting revision set to the specified cursor.
        ///
        /// - Parameter revision: The revision cursor from which the subscription should start.
        /// - Returns: A new options instance with the updated starting revision.
        @discardableResult
        public func startFrom(revision: RevisionCursor) -> Self {
            withCopy {
                $0.revision = revision
            }
        }

        /// Builds the gRPC options message for creating a persistent subscription on a specified stream.
        ///
        /// Maps the subscription settings and revision cursor to the appropriate fields in the underlying protobuf message.
        ///
        /// - Returns: The constructed gRPC options message for the create persistent subscription request.
        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)
                $0.stream = .with {
                    switch revision {
                    case .start:
                        $0.start = .init()
                    case .end:
                        $0.end = .init()
                    case let .specified(revision):
                        $0.revision = revision
                    }
                }
            }
        }
    }
}
