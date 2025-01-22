//
//  StreamClient.Tombstone.swift
//
//
//  Created by Grady Zhuo on 2023/11/2.
//
import KurrentCore
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

public struct Tombstone: UnaryUnary {
    public typealias Client = Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Tombstone.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Tombstone.Output

    public let streamIdentifier: Stream.Identifier
    public let options: Options
    
    package func requestMessage() throws -> UnderlyingRequest {
        return try .with {
            var options = options.build()
            options.streamIdentifier = try streamIdentifier.build()
            $0.options = options
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.tombstone(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
}

extension Tombstone {
    public struct Response: GRPCResponse {
        public typealias PositionOption = Stream.Position.Option

        public typealias UnderlyingMessage = UnderlyingResponse

        public internal(set) var position: PositionOption

        public init(from message: UnderlyingMessage) throws {
            let position: PositionOption?  = message.positionOption.map{
                switch $0 {
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

extension Tombstone {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var expectedRevision: Stream.RevisionRule

        public init(expectedRevision: Stream.RevisionRule = .streamExists) {
            self.expectedRevision = expectedRevision
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
        public func revision(expected expectedRevision: Stream.RevisionRule) -> Self {
            withCopy { options in
                options.expectedRevision = expectedRevision
            }
        }
    }
}
