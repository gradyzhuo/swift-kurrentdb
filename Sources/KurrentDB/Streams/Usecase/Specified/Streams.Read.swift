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
        public typealias Responses = AsyncThrowingStream<Response, Error>

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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions, completion: @Sendable @escaping ((any Error)?)->Void) async throws -> Responses {
            try await withThrowingTaskGroup(of: Void.self) { _ in
                let client = ServiceClient(wrapping: connection)
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                continuation.onTermination = { termination in
                    if case .finished(let error) = termination, let error {
                        completion(error)
                    }
                    completion(nil)
                }
                try await client.read(request: request, options: callOptions) {
                    do{
                        for try await message in $0.messages {
                            try continuation.yield(handle(message: message))
                        }
                        continuation.finish()
                    }catch{
                        
                        continuation.finish(throwing: error)
                    }
                    
                }
                return stream
            }
        }
    }
}

extension Streams.Read {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var revision: RevisionCursor
        public private(set) var direction: Direction
        public private(set) var resolveLinks: Bool
        public private(set) var limit: UInt64
        public private(set) var uuidOption: UUIDOption
        public private(set) var compatibility: UInt32

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

        @discardableResult
        public func resolveLinks(_ value: Bool = true) -> Self {
            withCopy { options in
                options.resolveLinks = value
            }
        }

        @discardableResult
        public func limit(_ limit: UInt64) -> Self {
            withCopy { options in
                options.limit = limit
            }
        }

        @discardableResult
        public func uuidOption(_ uuidOption: UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        @discardableResult
        public func compatibility(_ compatibility: UInt32) -> Self {
            withCopy { options in
                options.compatibility = compatibility
            }
        }

        @discardableResult
        public func forward() -> Self {
            withCopy { options in
                options.direction = .forward
            }
        }

        /// Returns a copy of the options with the read direction set to backward.
        @discardableResult
        public func backward() -> Self {
            withCopy { options in
                options.direction = .backward
            }
        }

        /// Returns a copy of the options with the specified stream revision and adjusts the read direction if the revision is `.start` (sets to forward) or `.end` (sets to backward).
        ///
        /// - Parameter revision: The stream revision to start reading from.
        /// Returns a copy of the options with the specified stream revision and adjusts the read direction accordingly.
        ///
        /// If the revision is `.start`, the direction is set to forward. If `.end`, the direction is set to backward. For `.specified`, the current direction is retained.
        ///
        /// - Parameter revision: The stream revision to start reading from.
        /// - Returns: A modified copy of the options with the updated revision and direction.
        @discardableResult
        public func startFrom(revision: RevisionCursor) -> Self {
            withCopy { options in
                options.revision = revision
                switch revision {
                case .start:
                    options.direction = .forward
                case .end:
                    options.direction = .backward
                case .specified:
                    options.direction = options.direction
                }
            }
        }

        /// Returns a copy of the options with the stream revision set to the specified value.
        ///
        /// - Parameter revision: The stream revision to start reading from.
        /// - Returns: A new `Options` instance with the updated revision, preserving the current read direction.
        @discardableResult
        public func revision(from revision: UInt64) -> Self {
            withCopy { options in
                options.revision = .specified(revision)
                options.direction = options.direction
            }
        }
    }
}

// MARK: - Deprecated

extension Streams.Read.Options {
    @available(*, deprecated, renamed: "limit")
    @discardableResult
    public func set(limit: UInt64) -> Self {
        withCopy { options in
            options.limit = limit
        }
    }

    @available(*, deprecated, renamed: "resolveLinks")
    @discardableResult
    public func set(resolveLinks: Bool) -> Self {
        withCopy { options in
            options.resolveLinks = resolveLinks
        }
    }

    @available(*, deprecated, renamed: "uuidOption")
    @discardableResult
    public func set(uuidOption: UUIDOption) -> Self {
        withCopy { options in
            options.uuidOption = uuidOption
        }
    }

    @available(*, deprecated, renamed: "compatibility")
    @discardableResult
    public func set(compatibility: UInt32) -> Self {
        withCopy { options in
            options.compatibility = compatibility
        }
    }
}
