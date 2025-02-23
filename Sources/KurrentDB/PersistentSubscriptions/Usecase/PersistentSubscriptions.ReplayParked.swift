//
//  PersistentSubscriptions.ReplayParked.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct ReplayParked: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.ReplayParked.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.ReplayParked.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let streamSelection: StreamSelector<StreamIdentifier>
        let groupName: String
        let options: Options

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
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

        package func send(client: UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.replayParked(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension PersistentSubscriptions.ReplayParked {
    public struct Options: EventStoreOptions {
        public enum StopAtOption {
            case position(position: Int64)
            case noLimit
        }

        package typealias UnderlyingMessage = UnderlyingRequest.Options

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
