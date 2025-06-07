//
//  PersistentSubscriptions.UpdateToAll.swift
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
        

        public private(set) var streamIdentifier: StreamIdentifier
        public private(set) var group: String
        public private(set) var options: Options

        init(streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request message for updating a persistent subscription.
        ///
        /// Builds the request based on the stream selection (all streams or a specific stream) and the provided cursor position or revision. Throws an error if the stream identifier cannot be built.
        ///
        /// - Throws: An error if building the stream identifier fails.
        /// - Returns: The constructed gRPC request message for the update operation.
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.streamIdentifier = try streamIdentifier.build()
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


extension PersistentSubscriptions.SpecifiedStream.Update{
    public struct Options: EventStoreOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.UpdateSettings
        public private(set) var revision: RevisionCursor?
        
        public init() {
            self.settings = .init()
        }


        @discardableResult
        public func startFrom(revision: RevisionCursor) -> Self {
            withCopy { 
                $0.revision = revision
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .from(settings: settings)
                if let revision {
                    switch revision {
                    case .start:
                        $0.stream.start = .init()
                    case .end:
                        $0.stream.end = .init()
                    case .specified(let revision):
                        $0.stream.revision = revision
                    }
                }
                
            }
        }
    }
}
