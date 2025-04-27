//
//  PersistentSubscriptions.UpdateToAll.swift
//  KurrentPersistentSubscriptions
//
//  Created by 卓俊諺 on 2025/1/13.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct Update: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>
        

        let streamSelection: StreamSelection
        public private(set) var group: String
        public private(set) var options: Options

        init(stream streamSelection: StreamSelection, group: String, options: Options) {
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
            return try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}


extension PersistentSubscriptions.Update{
    public struct Options: EventStoreOptions, PersistentSubscriptionsSettingsBuildable {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var settings: PersistentSubscription.Settings

        public init() {
            self.settings = .init()
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .from(settings: settings)
            }
        }
    }
}
