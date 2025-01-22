//
//  PersistentSubscriptionsClient.CreateToStream.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//
import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct CreateToStream: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>
    
    var streamIdentifier: Stream.Identifier
    var groupName: String
    var options: Options
    
    public init(streamIdentifier: Stream.Identifier, groupName: String, options: Options) {
        self.streamIdentifier = streamIdentifier
        self.groupName = groupName
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            $0.options = options.build()
            $0.options.groupName = groupName
            $0.options.stream.streamIdentifier = try streamIdentifier.build()
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.create(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}


extension CreateToStream{
    public struct Options: PersistentSubscriptionsCommonOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options
        
        public var settings: PersistentSubscription.Settings
        public var revisionCursor: Cursor<Stream.Revision>

        public init(settings: PersistentSubscription.Settings = .init(), revisionCursor: Cursor<Stream.Revision> = .end) {
            self.settings = settings
            self.revisionCursor = revisionCursor
        }

        @discardableResult
        public func startFrom(revision: Cursor<Stream.Revision>) -> Self {
            withCopy { options in
                options.revisionCursor = revision
            }
        }
        
        @discardableResult
        public mutating func set(consumerStrategy: PersistentSubscription.SystemConsumerStrategy) -> Self {
            withCopy { options in
                options.settings.consumerStrategy = consumerStrategy
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)

                switch revisionCursor {
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
