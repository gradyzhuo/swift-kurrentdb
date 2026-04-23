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
        package typealias Responses = PersistentSubscriptions.Subscription<PersistentSubscription.EventResult>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Read.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

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
            let writer = PersistentSubscriptions.Subscription<PersistentSubscription.EventResult>.Writer()
            let subscription = PersistentSubscriptions.Subscription(writer: writer)
            let task = Task {
                do {
                    let client = ServiceClient(wrapping: connection)
                    try await withRethrowingError(usage: "PersistentSubscription.SpecifiedStream.Read") {
                        try await client.read(metadata: metadata, options: callOptions) {
                            let requestMessages = try requestMessages()
                            try await $0.write(contentsOf: requestMessages)
                            try await $0.write(contentsOf: writer.sender)
                        } onResponse: {
                            for try await message in $0.messages {
                                let response = try handle(message: message)
                                switch response {
                                case let .confirmation(subscriptionId):
                                    subscription.send(state: .confirmation(subscriptionId: subscriptionId))
                                case let .readEvent(event, retryCount):
                                    subscription.send(state: .response(eventResult: .init( event: event, retryCount: retryCount)))
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

extension PersistentSubscriptions.SpecifiedStream.Read {
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public var bufferSize: Int32
        public var uuidOption: UUID.Option

        public init() {
            bufferSize = 1000
            uuidOption = .string
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
