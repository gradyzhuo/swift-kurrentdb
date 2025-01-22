//
//  PersistentSubscriptionsClient.UpdateToAll.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/13.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct UpdateToAll: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    var groupName: String
    var options: Options
    
    internal init(groupName: String, options: Options) {
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
        return try await client.update(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}


extension UpdateToAll {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings
        public var positionCursor: KurrentCore.Cursor<KurrentCore.Stream.Position>

        public init(settings: PersistentSubscription.Settings = .init(), positionCursor: KurrentCore.Cursor<KurrentCore.Stream.Position> = .end) {
            self.settings = settings
            self.positionCursor = positionCursor
        }
        
        @discardableResult
        public func startFrom(cursor: KurrentCore.Cursor<KurrentCore.Stream.Position>) -> Self {
            withCopy { options in
                options.positionCursor = cursor
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
            }
        }
    }
}
