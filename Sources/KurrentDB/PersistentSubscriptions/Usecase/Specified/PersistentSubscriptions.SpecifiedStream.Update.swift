//
//  PersistentSubscriptions.SpecifiedStream.Update.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/13.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
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

        public private(set) var streamIdentifier: StreamIdentifier
        public private(set) var group: String
        public private(set) var options: Options

        public init(streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request message for updating a persistent subscription.
        ///
        /// Builds the request based on the stream selection (all streams or a specific stream) and the provided cursor position or revision. Throws an error if the stream identifier cannot be built.
        ///
        /// - Throws: An error if building the stream identifier fails.
        /// Constructs the underlying gRPC request message for updating a persistent subscription on a specified stream.
        ///
        /// - Throws: An error if the stream identifier cannot be built.
        /// - Returns: The fully constructed gRPC request message.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }

        /// Sends an update request for a persistent subscription to a specified stream using the underlying gRPC client.
        ///
        /// - Returns: A wrapped response indicating the result of the update operation.
        ///
        /// - Throws: An error if the request fails or the response cannot be handled.
        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.SpecifiedStream.Update {
    public struct Options: CommandOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.UpdateSettings
        public private(set) var revision: RevisionCursor?

        public init() {
            settings = .init()
        }

        /// Returns a copy of the options with the starting revision set to the specified cursor.
        ///
        /// - Parameter revision: The stream revision from which the subscription should start.
        /// - Returns: A modified copy of the options with the updated starting revision.
        @discardableResult
        public func startFrom(revision: RevisionCursor) -> Self {
            withCopy {
                $0.revision = revision
            }
        }

        /// Constructs the underlying gRPC options message for updating a persistent subscription.
        ///
        /// Maps the current settings and revision cursor to the appropriate fields in the gRPC message.
        ///
        /// - Returns: The configured gRPC options message for the update request.
        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .from(settings: settings)
                if let revision {
                    switch revision {
                    case .start:
                        $0.stream.start = .init()
                    case .end:
                        $0.stream.end = .init()
                    case let .specified(revision):
                        $0.stream.revision = revision
                    }
                }
            }
        }
    }
}
