//
//  Streams.Read.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2023/10/21.
//

import GRPCCore
import GRPCEncapsulates

extension Streams{
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

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
            
            return try await withThrowingTaskGroup(of: Void.self) { _ in
                let client = ServiceClient(wrapping: connection)
                let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
                try await client.read(request: request, options: callOptions) {
                    for try await message in $0.messages {
                        try continuation.yield(handle(message: message))
                    }
                    continuation.finish()
                }
                return stream
            }
        }
    }
}

extension Streams.Read {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        private var cursor: RevisionCursor
        public package(set) var direction: Direction
        public package(set) var resolveLinks: Bool
        public package(set) var limit: UInt64
        public package(set) var uuidOption: UUIDOption
        public package(set) var compatibility: UInt32
        

        public init() {
            self.resolveLinks = false
            self.limit = .max
            self.uuidOption = .string
            self.compatibility = 0
            self.cursor = .start
            self.direction = .forward
        }

        
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
                
                switch cursor {
                case .start:
                    $0.stream.start = .init()
                case .end:
                    $0.stream.end = .init()
                case let .revision(revision):
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
            withCopy{ options in
                options.direction = .forward
            }
        }
        
        @discardableResult
        public func backward() -> Self {
            withCopy{ options in
                options.direction = .backward
            }
        }
        
        @discardableResult
        internal func cursor(_ cursor: RevisionCursor) -> Self {
            withCopy{ options in
                options.cursor = cursor
                switch cursor {
                case .start:
                    options.direction = .forward
                case .end:
                    options.direction = .backward
                case .revision:
                    options.direction = options.direction
                }
            }
        }
    }
}



//MARK: - Deprecated
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
