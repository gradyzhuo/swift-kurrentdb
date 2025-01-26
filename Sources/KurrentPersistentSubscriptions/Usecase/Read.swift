//
//  PersistentSubscriptionsClient.Read.swift
//
//
//  Created by Grady Zhuo on 2023/12/8.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates
import Foundation

extension PersistentSubscriptions {
    public struct Read: StreamStream {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Read.Output
        package typealias Responses = Subscription

        public let streamSelection: StreamSelector<StreamIdentifier>
        public let groupName: String
        public let options: Options
        
        internal init(streamSelection: StreamSelector<StreamIdentifier>, groupName: String, options: Options) {
            self.streamSelection = streamSelection
            self.groupName = groupName
            self.options = options
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            return try [
                .with {
                    $0.options = options.build()
                    if case let .specified(streamIdentifier) = streamSelection {
                        $0.options.streamIdentifier = try streamIdentifier.build()
                    } else {
                        $0.options.all = .init()
                    }
                    $0.options.groupName = groupName
                },
            ]
        }
        
        
        package func send(client: Client, metadata: Metadata, callOptions: CallOptions) async throws -> Responses {
            let responses = AsyncThrowingStream.makeStream(of: Response.self)
            
            let writer = Subscription.Writer()
            let requestMessages = try requestMessages()
            writer.write(messages: requestMessages)
            Task{
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

extension PersistentSubscriptions.Read {
    public enum Response: GRPCResponse {
        package typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ReadResp

        case readEvent(event: ReadEvent, retryCount: Int32)
        case confirmation(subscriptionId: String)

        package init(from message: UnderlyingMessage) throws {
            guard let content = message.content else {
                throw EventStoreError.resourceNotFound(reason: "The content of PersistentSubscriptions Read Response is missing.")
            }
            switch content {
            case let .event(eventMessage):
                self = try .readEvent(event: .init(message: eventMessage), retryCount: eventMessage.retryCount)
            case let .subscriptionConfirmation(subscriptionConfirmation):
                self = .confirmation(subscriptionId: subscriptionConfirmation.subscriptionID)
            }
        }
    }
}

extension PersistentSubscriptions.Read {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public private(set) var bufferSize: Int32
        public private(set) var uuidOption: UUID.Option

        public init() {
            bufferSize = 1000
            uuidOption = .string
        }

        public func set(bufferSize: Int32) -> Self {
            withCopy { options in
                options.bufferSize = bufferSize
            }
        }

        public func set(uuidOption: UUID.Option) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
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
