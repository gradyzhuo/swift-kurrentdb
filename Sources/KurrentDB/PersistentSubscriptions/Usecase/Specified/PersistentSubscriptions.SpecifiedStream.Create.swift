//
//  PersistentSubscriptions.CreateToAll.swift
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
        /// - Throws: An error if building the stream identifier fails.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
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


extension PersistentSubscriptions.SpecifiedStream.Create {
    public struct Options: EventStoreOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.CreateSettings
        public private(set) var revision: RevisionCursor

        public init() {
            self.settings = .init()
            self.revision = .end
        }

        @discardableResult
        public func startFrom(revision: RevisionCursor) -> Self {
            withCopy { 
                $0.revision = revision 
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)
                $0.stream = .with{
                    switch revision {
                    case .start:
                        $0.start = .init()
                    case .end:
                        $0.end = .init()
                    case .specified(let revision):
                        $0.revision = revision
                    }
                }
                
            }
        }
    }
}
