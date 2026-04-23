//
//  PersistentSubscriptions.SpecifiedStream.Create.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    /// Usecase for creating a persistent subscription on a specific named stream.
    public struct Create: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Create.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        let streamIdentifier: StreamIdentifier
        let group: String
        let options: Options

        public init(streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

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
    /// Configuration options for creating a persistent subscription on a specified stream.
    public struct Options: CommandOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// The subscription creation settings such as consumer strategy, timeouts, and retry behaviour.
        public var settings: PersistentSubscription.CreateSettings
        /// The starting revision in the stream from which events will be delivered.
        public var revision: RevisionCursor

        public init() {
            settings = .init()
            revision = .end
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
