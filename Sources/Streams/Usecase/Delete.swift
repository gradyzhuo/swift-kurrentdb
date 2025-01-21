//
//  StreamClient.Delete.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2023/10/31.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct Delete: UnaryUnary {
    public typealias Client = Streams.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Delete.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Delete.Output

    public let streamIdentifier: Stream.Identifier
    public let options: Options
    
    internal init(streamIdentifier: Stream.Identifier, options: Options) {
        self.streamIdentifier = streamIdentifier
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            $0.options = options.build()
            $0.options.streamIdentifier = try streamIdentifier.build()
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
        return try await client.delete(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
    
}

extension Delete {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = UnderlyingResponse

        public internal(set) var position: Stream.Position.Option

        public init(from message: UnderlyingMessage) throws {
            let position: Stream.Position.Option? = message.positionOption.map{
                return switch $0 {
                case let .position(position):
                    .position(.at(commitPosition: position.commitPosition, preparePosition: position.preparePosition))
                case .noPosition:
                    .noPosition
                }
            }
            self.position = position ?? .noPosition
        }
    }
}

extension Delete {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var expectedRevision: Stream.RevisionRule

        public init() {
            expectedRevision = .streamExists
        }

        public func build() -> UnderlyingMessage {
            .with {
                switch expectedRevision {
                case .any:
                    $0.any = .init()
                case .noStream:
                    $0.noStream = .init()
                case .streamExists:
                    $0.streamExists = .init()
                case let .revision(rev):
                    $0.revision = rev
                }
            }
        }

        @discardableResult
        public func revision(expected: Stream.RevisionRule) -> Self {
            withCopy { options in
                options.expectedRevision = expected
            }
        }
    }
}
