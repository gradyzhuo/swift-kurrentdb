//
//  PersistentSubscriptionsClient.ReplayParked.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct ReplayParked: UnaryUnary {
    public typealias Client = PersistentSubscriptions.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.ReplayParked.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.ReplayParked.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    let streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>
    let groupName: String
    let options: Options
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            $0.options = options.build()
            $0.options.groupName = groupName

            switch streamSelection {
            case .all:
                $0.options.all = .init()
            case let .specified(streamIdentifier):
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.replayParked(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension ReplayParked {
    public struct Options: EventStoreOptions {
        public enum StopAtOption {
            case position(position: Int64)
            case noLimit
        }
        public typealias UnderlyingMessage = UnderlyingRequest.Options
        
        var message: UnderlyingMessage

        public init() {
            message = .init()
            stop(at: .noLimit)
        }

        @discardableResult
        public func stop(at option: StopAtOption) -> Self {
            withCopy { options in
                switch option {
                case let .position(position):
                    options.message.stopAt = position
                case .noLimit:
                    options.message.noLimit = .init()
                }
            }
        }

        package func build() -> UnderlyingRequest.Options {
            message
        }
    }
}
