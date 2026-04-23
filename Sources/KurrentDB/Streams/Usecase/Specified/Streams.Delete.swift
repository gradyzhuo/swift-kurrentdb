//
//  Streams.Delete.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/31.
//

import GRPCCore
import GRPCEncapsulates

extension Streams {
    /// Usecase that soft-deletes a stream, allowing it to be recreated later.
    public struct Delete: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Delete.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Delete.Output

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Delete.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        /// Identifier of the stream to delete.
        public let streamIdentifier: StreamIdentifier
        /// Options controlling the delete behaviour (e.g. expected revision).
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
    /// Response returned after a successful stream deletion.
    public struct Response: GRPCResponse {
        package typealias UnderlyingMessage = UnderlyingResponse

        /// Global log position of the delete operation, or `nil` when unavailable.
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
    /// Options that control stream delete behaviour.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// Expected stream revision used for optimistic concurrency checks.
        public var expectedRevision: StreamRevision

        /// Initialises options with `expectedRevision` set to `.streamExists`.
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
    }
}
