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
    /// Usecase for reading events from a persistent subscription on the `$all` stream.
    public struct Read: StreamStream {
        package typealias ServiceClient = PersistentSubscriptions.UnderlyingClient
        package typealias UnderlyingRequest = PersistentSubscriptions.UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = PersistentSubscriptions.UnderlyingService.Method.Read.Output
        package typealias Response = PersistentSubscriptions.ReadResponse
        package typealias Responses = PersistentSubscriptions.Subscription<PersistentSubscription.EventResult>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Read.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        /// The stream identifier, always `nil` for the `$all` stream.
        public let streamIdentifier: StreamIdentifier?
        /// The consumer group name for the persistent subscription.
        public let group: String
        /// The read options for this subscription request.
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
            let writer = PersistentSubscriptions.Subscription<PersistentSubscription.EventResult>.Writer()
            let subscription = PersistentSubscriptions.Subscription(writer: writer)
            let requestMessages = try requestMessages()
            writer.write(messages: requestMessages)
            let task = Task {
                do {
                    let client = ServiceClient(wrapping: connection)

                    try await withRethrowingError(usage: "PersistentSubscription.AllStream.Read") {
                        try await client.read(metadata: metadata, options: callOptions) {
                            try await $0.write(contentsOf: writer.sender)
                        } onResponse: {
                            for try await message in $0.messages {
                                let response = try handle(message: message)
                                switch response {
                                case let .confirmation(subscriptionId):
                                    subscription.send(state: .confirmation(subscriptionId: subscriptionId))
                                case let .readEvent(event, retryCount):
                                    subscription.send(state: .response(eventResult: .init(event: event, retryCount: retryCount)))
                                }
                            }
                            subscription.send(state: .finish())
                        }
                    }
                } catch {
                    subscription.send(state: .finish(throwing: error))
                }
            }
            
            subscription.onFinish { termination in
                if case let .finished(error) = termination {
                    completion(error)
                } else {
                    completion(nil)
                }
                task.cancel()
            }

            return subscription
        }
    }
}

extension PersistentSubscriptions.AllStream.Read {
    /// Configuration options for reading from a persistent subscription on the `$all` stream.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// The maximum number of messages to buffer before applying back-pressure.
        public var bufferSize: Int32
        /// The UUID representation format used for event identifiers in the response.
        public var uuidOption: UUID.Option

        public init() {
            bufferSize = 1000
            uuidOption = .string
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
