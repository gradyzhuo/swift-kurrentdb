//
//  Streams.Read.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/21.
//

import GRPCCore
import GRPCEncapsulates

extension Streams {
    public struct Read: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Read.Output
        public typealias Response = ReadResponse
        public typealias Responses = AsyncThrowingStream<Response, any Error>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Read.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        public let streamIdentifier: StreamIdentifier
        public let options: Options

        init(from streamIdentifier: StreamIdentifier, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                $0.options = options.build()
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<ServiceClient.UnderlyingService.Method.Read.Input>, callOptions: CallOptions, completion: @escaping @Sendable ((any Error)?) -> Void) async throws -> AsyncThrowingStream<Response, any Error> {
            let client = ServiceClient(wrapping: connection)
            return try await client.read(request: request, options: callOptions) {
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                continuation.onTermination = { termination in
                    if case let .finished(error) = termination {
                        completion(error)
                    } else {
                        completion(nil)
                    }
                }
                do {
                    for try await message in $0.messages {
                        try continuation.yield(handle(message: message))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                return stream
            }
        }
    }
}

extension Streams.Read {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var revision: RevisionCursor
        public var direction: Direction
        public var resolveLinks: Bool
        public var limit: UInt64
        public var uuidOption: UUIDOption
        public var compatibility: UInt32

        public init() {
            resolveLinks = false
            limit = .max
            uuidOption = .string
            compatibility = 0
            revision = .start
            direction = .forward
        }

        /// Constructs and returns the underlying GRPC message for a stream read operation using the current options.
        ///
        /// The message includes stream position, read direction, link resolution, event limit, UUID format, and compatibility settings.
        package func build() -> UnderlyingMessage {
            .with {
                $0.noFilter = .init()

                switch uuidOption {
                case .structured:
                    $0.uuidOption.structured = .init()
                case .string:
                    $0.uuidOption.string = .init()
                }

                $0.controlOption = .with {
                    $0.compatibility = compatibility
                }
                $0.resolveLinks = resolveLinks
                $0.count = limit

                switch revision {
                case .start:
                    $0.stream.start = .init()
                case .end:
                    $0.stream.end = .init()
                case let .specified(revision):
                    $0.stream.revision = revision
                }

                $0.readDirection = switch direction {
                case .forward:
                    .forwards
                case .backward:
                    .backwards
                }
            }
        }
    }
}
