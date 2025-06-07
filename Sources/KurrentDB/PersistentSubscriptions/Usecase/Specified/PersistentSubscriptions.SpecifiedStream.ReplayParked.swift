//
//  PersistentSubscriptions.SpecifiedStream.ReplayParked.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct ReplayParked: UnaryUnary {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.ReplayParked.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.ReplayParked.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        let streamIdentifier: StreamIdentifier
        let group: String
        let options: Options
        
        init(stream streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }
        
        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.groupName = group
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.replayParked(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}


extension PersistentSubscriptions.SpecifiedStream.ReplayParked {
    public struct Options: EventStoreOptions {
        public enum StopAtOption: Sendable {
            case position(position: Int64)
            case noLimit
        }

        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var stopAt: StopAtOption

        public init() {
            stopAt = .noLimit
        }

        @discardableResult
        public func stopAt(_ stopAt: StopAtOption) -> Self {
            return withCopy { options in
                options.stopAt = stopAt
            }            
        }

        package func build() -> UnderlyingMessage {
            return .with { 
                $0.all = .init()
                switch stopAt {
                case .noLimit:
                    $0.noLimit = .init()
                case let .position(position):
                    $0.stopAt = position
                }
            }
        }
    }
}
