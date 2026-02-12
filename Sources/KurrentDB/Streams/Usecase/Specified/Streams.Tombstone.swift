//
//  Tombstone.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/11/2.
//
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix

extension Streams {
    public struct Tombstone: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Tombstone.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Tombstone.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor{
            get{
                ServiceClient.UnderlyingService.Method.Tombstone.descriptor
            }
        }

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
                var options = options.build()
                options.streamIdentifier = try streamIdentifier.build()
                $0.options = options
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.tombstone(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Streams.Tombstone {
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

extension Streams.Tombstone {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var expectedRevision: StreamRevision

        public init(expectedRevision: StreamRevision = .streamExists) {
            self.expectedRevision = expectedRevision
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
        public func revision(expected expectedRevision: StreamRevision) -> Self {
            withCopy { options in
                options.expectedRevision = expectedRevision
            }
        }
    }
}
