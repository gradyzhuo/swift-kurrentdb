//
//  PersistentSubscriptions.CreateToAll.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/12.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct Create: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Create.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Create.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>
        
        let streamSelection: StreamSelection
        let group: String
        let options: Options

        public init(stream streamSelection: StreamSelection, group: String, options: Options) {
            self.streamSelection = streamSelection
            self.group = group
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                switch streamSelection {
                case .all(let cursor):
                    $0.options.all = .with{
                        switch cursor {
                        case .start:
                            $0.start = .init()
                        case .end:
                            $0.end = .init()
                        case let .position(commitPosition, preparePosition):
                            $0.position = .with {
                                $0.commitPosition = commitPosition
                                $0.preparePosition = preparePosition
                            }
                        }
                    }
                case .specified(let identifier, let cursor):
                    $0.options.stream = try .with{
                        $0.streamIdentifier = try identifier.build()
                        switch cursor {
                        case .start:
                            $0.start = .init()
                        case .end:
                            $0.end = .init()
                        case .revision(let revision):
                            $0.revision = revision
                        }
                    }
                    
                }
                
                
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


extension PersistentSubscriptions.Create {
    public struct Options: EventStoreOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings
        public var filter: SubscriptionFilter?
        public var cursor: PositionCursor

        public init() {
            self.settings = .init()
            self.filter = nil
            self.cursor = .end
        }

        @discardableResult
        public func filter(_ filter: SubscriptionFilter) -> Self {
            withCopy { $0.filter = filter }
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .make(settings: settings)

                if let filter {
                    $0.all.filter = .make(with: filter)
                } else {
                    $0.all.noFilter = .init()
                }
            }
        }
    }
}
