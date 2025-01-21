//
//  PersistentSubscriptionsClient.CreateToAll.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/12.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct CreateToAll: UnaryUnary {
    public typealias Client = PersistentSubscriptions.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>
    
    let groupName: String
    let options: Options
    
    public init(groupName: String, options: Options) {
        self.groupName = groupName
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
            $0.options.groupName = groupName
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.create(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension CreateToAll{
    public struct Options: PersistentSubscriptionsCommonOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings
        public var filter: Stream.SubscriptionFilter?
        public var positionCursor: Cursor<Stream.Position>

        public init(settings: PersistentSubscription.Settings = .init(), filter: Stream.SubscriptionFilter? = nil, positionCursor: Cursor<Stream.Position> = .end) {
            self.settings = settings
            self.filter = filter
            self.positionCursor = positionCursor
        }

        @discardableResult
        public func startFrom(position: Cursor<Stream.Position>) -> Self {
            withCopy { options in
                options.positionCursor = position
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
                switch positionCursor {
                case .start:
                    $0.all.start = .init()
                case .end:
                    $0.all.end = .init()
                case let .specified(pointer):
                    $0.all.position = .with {
                        $0.commitPosition = pointer.commit
                        $0.preparePosition = pointer.prepare
                    }
                }

                if let filter {
                    $0.all.filter = .make(with: filter)
                } else {
                    $0.all.noFilter = .init()
                }
            }
        }
    }
}
