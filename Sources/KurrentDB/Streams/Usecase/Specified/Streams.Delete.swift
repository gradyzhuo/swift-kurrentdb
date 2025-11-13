//
//  Streams.Delete.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/31.
//

import GRPCCore
import GRPCEncapsulates

extension Streams {
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Delete.Output
        
        package static var name: String{
            get{
                "Streams.\(Self.self)"
            }
        }
        
        public let streamIdentifier: StreamIdentifier
        public let options: Options

        init(to streamIdentifier: StreamIdentifier, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: GRPCCore.ClientRequest<UnderlyingRequest>, callOptions: GRPCCore.CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.delete(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.Delete {
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        public internal(set) var position: StreamPosition?

        package init(from message: UnderlyingMessage) throws {
            position = message.positionOption.flatMap {
                switch $0 {
                case let .position(position):
                    .at(commitPosition: position.commitPosition, preparePosition: position.preparePosition)
                case .noPosition:
                    nil
                }
            }
        }
    }
}

extension Streams.Delete {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var expectedRevision: StreamRevision

        public init() {
            expectedRevision = .streamExists
        }

        package func build() -> UnderlyingMessage {
            .with {
                switch expectedRevision {
                case .any:
                    $0.any = .init()
                case .noStream:
                    $0.noStream = .init()
                case .streamExists:
                    $0.streamExists = .init()
                case let .at(revision):
                    $0.revision = revision
                }
            }
        }

        @discardableResult
        public func revision(expected: StreamRevision) -> Self {
            withCopy { options in
                options.expectedRevision = expected
            }
        }
    }
}
