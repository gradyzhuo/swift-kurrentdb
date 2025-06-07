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

        public let streamIdentifier: StreamIdentifier?
        public let group: String
        public let options: Options

        init(group: String, options: Options) {
            self.streamIdentifier = nil
            self.group = group
            self.options = options
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            [
                .with {
                    $0.options = options.build()
                    $0.options.groupName = group
                },
            ]
        }

        package func send(connection: GRPCClient<Transport>, metadata: Metadata, callOptions: CallOptions) async throws -> Responses {
            let responses = AsyncThrowingStream.makeStream(of: Response.self)

            let writer = PersistentSubscriptions.Subscription.Writer()
            let requestMessages = try requestMessages()
            writer.write(messages: requestMessages)
            Task {
                let client = ServiceClient(wrapping: connection)
                try await client.read(metadata: metadata, options: callOptions) {
                    try await $0.write(contentsOf: writer.sender)
                } onResponse: {
                    for try await message in $0.messages {
                        let response = try handle(message: message)
                        responses.continuation.yield(response)
                    }
                }
            }
            return try await .init(requests: writer, responses: responses.stream)
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

        public func bufferSize(_ bufferSize: Int32) -> Self {
            withCopy { options in
                options.bufferSize = bufferSize
            }
        }

        public func uuidOption(_ uuidOption: UUID.Option) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

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