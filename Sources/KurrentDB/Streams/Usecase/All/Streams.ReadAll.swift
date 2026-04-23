//
//  Streams.ReadAll.swift
//  KurrentStreams
//
//  Created by 卓俊諺 on 2025/1/3.
//

import GRPCCore
import GRPCEncapsulates

extension Streams where Target == AllStreamsTarget {
    /// Usecase that reads events from the global `$all` stream.
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

        /// Options controlling which events are returned and in what order.
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

extension Streams.ReadAll where Target == AllStreamsTarget {
    /// A position-and-direction pair used to anchor a `$all` read operation.
    public struct CursorPointer: Sendable {
        /// Global log position at which to anchor the read.
        public let position: StreamPosition
        /// Direction in which to read from the anchor position.
        public let direction: Direction

        /// Creates a forward cursor anchored at the given commit and prepare positions.
        public static func forwardOn(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .forward)
        }

        /// Creates a backward cursor anchored at the given commit and prepare positions.
        public static func backwardFrom(commitPosition: UInt64, preparePosition: UInt64) -> Self {
            .init(position: .at(commitPosition: commitPosition, preparePosition: preparePosition), direction: .backward)
        }
    }
}

extension Streams.ReadAll {
    /// Options that control `$all` read behaviour.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// Global log position at which the read starts.
        public var position: PositionCursor
        /// Direction in which events are returned.
        public var direction: Direction
        /// When `true`, linked events are resolved to their targets.
        public var resolveLinksEnabled: Bool
        /// Maximum number of events to return.
        public var limit: UInt64
        /// UUID representation used in event metadata.
        public var uuidOption: UUIDOption
        /// Compatibility level passed to the server.
        public var compatibility: UInt32

        /// Initialises options with sensible defaults (start from beginning, forward, max events, string UUIDs).
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
