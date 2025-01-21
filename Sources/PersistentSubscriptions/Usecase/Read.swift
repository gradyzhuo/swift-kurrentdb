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

public struct Read: StreamStream {
    public typealias Client = PersistentSubscriptions.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Read.Output
    public typealias Responses = Subscription

    public let streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>
    public let groupName: String
    public let options: Options
    
    internal init(streamSelection: KurrentCore.Selector<KurrentCore.Stream.Identifier>, groupName: String, options: Options) {
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
    
    
//    public func perform(client: Client.UnderlyingClient, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses {
//        return try await client.read(request: request, options: callOptions) {
//            return try handle(response: $0)
//        }
//    }
    
    package func send(client: Client.UnderlyingClient, metadata: Metadata, callOptions: CallOptions) async throws -> Responses {
        let requests = AsyncStream.makeStream(of: UnderlyingRequest.self)
        let responses = AsyncThrowingStream.makeStream(of: Response.self)
        
        let writer = Subscription.Writer()
        Task{
            try await client.read(metadata: metadata, options: callOptions) {
                let requestMessage = try requestMessages()
                try await $0.write(contentsOf: requestMessage)
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

extension ReadEvent {
    package init(message: Read.Response.UnderlyingMessage.ReadEvent) throws {
        let recordedEvent: RecordedEvent = try .init(message: message.event)
        let linkedRecordedEvent: RecordedEvent? = try message.hasLink ? .init(message: message.link) : nil

        let commitPosition: KurrentCore.Stream.Position?
        if let position = message.position {
            switch position {
            case .noPosition:
                commitPosition = nil
            case let .commitPosition(position):
                commitPosition = .at(commitPosition: position)
            }
        } else {
            commitPosition = nil
        }
        
        self.init(event: recordedEvent, link: linkedRecordedEvent, commitPosition: commitPosition)
    }
}

extension Read {
    public enum Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ReadResp

        case readEvent(event: ReadEvent, retryCount: Int32)
        case confirmation(subscriptionId: String)

        public init(from message: UnderlyingMessage) throws {
            if message.event.isInitialized {
                let event = message.event
                self = try .readEvent(event: .init(message: event), retryCount: event.retryCount)
            } else {
                self = .confirmation(subscriptionId: message.subscriptionConfirmation.subscriptionID)
            }
        }
    }
}

extension Read {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

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
