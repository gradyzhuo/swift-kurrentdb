//
//  PersistentSubscriptions.SpecifiedStream.Read.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/8.
//
import Foundation
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions.SpecifiedStream {
    public struct Read: StreamStream {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Read.Output
        package typealias Response = PersistentSubscriptions.ReadResponse
        package typealias Responses = PersistentSubscriptions.Subscription

        public let streamIdentifier: StreamIdentifier
        public let group: String
        public let options: Options

        init(stream streamIdentifier: StreamIdentifier, group: String, options: Options) {
            self.streamIdentifier = streamIdentifier
            self.group = group
            self.options = options
        }

        /// Constructs the underlying gRPC request messages for initiating a persistent subscription read on a specified stream.
        ///
        /// - Returns: An array containing the configured request message.
        /// - Throws: An error if building the stream identifier fails.
        package func requestMessages() throws -> [UnderlyingRequest] {
            try [
                .with {
                    $0.options = options.build()
                    $0.options.groupName = group
                    $0.options.streamIdentifier = try streamIdentifier.build()
                },
            ]
        }

        /// Initiates an asynchronous gRPC streaming read from a persistent subscription on a specified stream.
        ///
        /// Sends the configured request messages to the server and returns a stream of subscription responses as they arrive. The returned object provides both the request writer and the asynchronous response stream.
        ///
        /// - Returns: An object containing the request writer and an asynchronous stream of subscription responses.
        /// - Throws: If building the request messages fails or if the gRPC call encounters an error.
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

extension PersistentSubscriptions.SpecifiedStream.Read {
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
        /// - Parameter bufferSize: The maximum number of events to buffer in the subscription.
        /// - Returns: A new `Options` instance with the updated buffer size.
        public func bufferSize(_ bufferSize: Int32) -> Self {
            withCopy { options in
                options.bufferSize = bufferSize
            }
        }

        /// Returns a copy of the options with the specified UUID representation option set.
        ///
        /// - Parameter uuidOption: The UUID representation to use for events.
        /// - Returns: A new options instance with the updated UUID option.
        public func uuidOption(_ uuidOption: UUID.Option) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        /// Builds and returns the underlying gRPC options message for the persistent subscription read request, configured with the current buffer size and UUID option.
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
