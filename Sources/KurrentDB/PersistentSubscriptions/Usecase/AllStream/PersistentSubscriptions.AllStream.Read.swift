//
//  PersistentSubscriptions.AllStream.Read.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/8.
//
import Foundation
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.AllStream {
    public struct Read: StreamStream {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Read.Output
        package typealias Response = PersistentSubscriptions.ReadResponse
        package typealias Responses = PersistentSubscriptions.Subscription
        
        package static var name: String{
            get{
                "PersistentSubscriptions.\(Self.self)"
            }
        }
        
        public let streamIdentifier: StreamIdentifier?
        public let group: String
        public let options: Options

        init(group: String, options: Options) {
            streamIdentifier = nil
            self.group = group
            self.options = options
        }

        /// Constructs the initial request message for reading from a persistent subscription to all streams.
        ///
        /// - Returns: An array containing a single request message with the configured group name and options.
        /// - Throws: An error if building the request message fails.
        package func requestMessages() throws -> [UnderlyingRequest] {
            [
                .with {
                    $0.options = options.build()
                    $0.options.groupName = group
                },
            ]
        }

        /// Initiates an asynchronous streaming read from a persistent subscription to all streams.
        ///
        /// Starts a gRPC streaming call using the provided connection, sending subscription request messages and yielding incoming responses as an asynchronous stream.
        ///
        /// - Returns: An object containing the request writer and the asynchronous stream of responses.
        ///
        /// - Throws: An error if request message construction fails or if the streaming call encounters an error.
        package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions, completion: @escaping @Sendable ((any Error)?) -> Void) async throws -> Responses {
            let (stream, continuation) = AsyncThrowingStream.makeStream(of: Response.self)
            continuation.onTermination = { termination in
                if case let .finished(error) = termination {
                    completion(error)
                } else {
                    completion(nil)
                }
            }

            let writer = PersistentSubscriptions.Subscription.Writer()
            let requestMessages = try requestMessages()
            writer.write(messages: requestMessages)
            Task {
                let client = ServiceClient(wrapping: connection)
                try await client.read(metadata: metadata, options: callOptions) {
                    try await $0.write(contentsOf: writer.sender)
                } onResponse: {
                    do {
                        for try await message in $0.messages {
                            let response = try handle(message: message)
                            continuation.yield(response)
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }
            return try await .init(requests: writer, responses: stream)
        }
    }
}

extension PersistentSubscriptions.AllStream.Read {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var bufferSize: Int32
        public private(set) var uuidOption: UUID.Option

        public init() {
            bufferSize = 1000
            uuidOption = .string
        }

        /// Returns a copy of the options with the buffer size set to the specified value.
        ///
        /// - Parameter bufferSize: The desired buffer size for the subscription read.
        /// - Returns: A new `Options` instance with the updated buffer size.
        public func bufferSize(_ bufferSize: Int32) -> Self {
            withCopy { options in
                options.bufferSize = bufferSize
            }
        }

        /// Returns a copy of the options with the specified UUID representation option set.
        ///
        /// - Parameter uuidOption: The desired UUID representation format.
        /// - Returns: A new `Options` instance with the updated UUID option.
        public func uuidOption(_ uuidOption: UUID.Option) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        /// Builds and returns the underlying gRPC message representing the subscription read options for all streams.
        ///
        /// The message includes the buffer size and the UUID representation option as configured in the options instance.
        ///
        /// - Returns: The constructed underlying message for the persistent subscription read request.
        package func build() -> UnderlyingMessage {
            .with {
                $0.all = .init()
                $0.bufferSize = bufferSize
                switch uuidOption {
                case .string:
                    $0.uuidOption.string = .init()
                case .structured:
                    $0.uuidOption.structured = .init()
                }
            }
        }
    }
}
