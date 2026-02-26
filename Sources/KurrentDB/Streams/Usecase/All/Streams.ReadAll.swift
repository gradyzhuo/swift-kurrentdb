//
//  Streams.ReadAll.swift
//  KurrentStreams
//
//  Created by 卓俊諺 on 2025/1/3.
//

import GRPCCore
import GRPCEncapsulates

extension Streams where Target == AllStreams {
    public struct ReadAll: UnaryStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Read.Output
        public typealias Response = ReadResponse
        public typealias Responses = AsyncThrowingStream<Response, Error>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Read.descriptor
        }

        package static var name: String {
            "Streams.\(Self.self)"
        }

        public let options: Options

        init(options: Options) {
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?) -> Void) async throws -> Responses {
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
                        do {
                            try continuation.yield(handle(message: message))
                        } catch {
                            continuation.finish(throwing: error)
                        }
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

extension Streams.ReadAll where Target == AllStreams {
    public struct CursorPointer: Sendable {
        public let position: StreamPosition
        public let direction: Direction

        public static func forwardOn(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .forward)
        }

        public static func backwardFrom(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .backward)
        }
    }
}

extension Streams.ReadAll {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var position: PositionCursor
        public var direction: Direction
        public var resolveLinksEnabled: Bool
        public var limit: UInt64
        public var uuidOption: UUIDOption
        public var compatibility: UInt32

        public init() {
            resolveLinksEnabled = false
            limit = .max
            uuidOption = .string
            compatibility = 0
            position = .start
            direction = .forward
        }

        /// Constructs the underlying gRPC request message for reading all streams using the configured options.
        ///
        /// The returned message includes settings for filters, UUID representation, compatibility, link resolution, count limit, stream position, and read direction.
        ///
        /// - Returns: A gRPC request message populated with the current options.
        package func build() -> UnderlyingMessage {
            .with {
                $0.noFilter = .init()
                $0.all = .init()

                switch uuidOption {
                case .structured:
                    $0.uuidOption.structured = .init()
                case .string:
                    $0.uuidOption.string = .init()
                }

                $0.controlOption = .with {
                    $0.compatibility = compatibility
                }
                $0.resolveLinks = resolveLinksEnabled
                $0.count = limit

                switch position {
                case .start:
                    $0.all.start = .init()
                case .end:
                    $0.all.end = .init()
                case let .specified(commitPosition, preparePosition):
                    $0.all.position = .with {
                        $0.commitPosition = commitPosition
                        $0.preparePosition = preparePosition
                    }
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
