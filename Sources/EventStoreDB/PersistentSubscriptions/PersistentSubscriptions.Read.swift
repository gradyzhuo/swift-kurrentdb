//
//  PersistentSubscriptions.Read.swift
//
//
//  Created by Grady Zhuo on 2023/12/8.
//

import Foundation
import GRPCSupport

extension PersistentSubscriptionsClient {
    public struct Read: StreamStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReadReq>

        let streamSelection: Selector<Stream.Identifier>
        let groupName: String
        let options: Options

        public func build() throws -> [Request.UnderlyingMessage] {
            try [
                .with {
                    $0.options = options.build()
                    if case let .specified(streamIdentifier) = streamSelection {
                        $0.options.streamIdentifier = try streamIdentifier.build()
                    } else {
                        $0.options.all = .init()
                    }
                    $0.options.groupName = groupName
                }
            ]
        } // End of build
    }
}

extension ReadEvent {
    init(message: EventStore_Client_PersistentSubscriptions_ReadResp.ReadEvent) throws {
        recordedEvent = try .init(message: message.event)
        linkedRecordedEvent = try message.hasLink ? .init(message: message.link) : nil

        if let position = message.position {
            switch position {
            case .noPosition:
                commitPosition = nil
            case let .commitPosition(commitPosition):
                self.commitPosition = .init(commit: commitPosition)
            }
        } else {
            commitPosition = nil
        }
    }
}

extension PersistentSubscriptionsClient.Read {
    public enum Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ReadResp
        
        case readEvent(event: ReadEvent, retryCount: Int32)
        case confirmation(subscriptionId: String)
        
        public init(from message: UnderlyingMessage) throws {
            if message.event.isInitialized {
               let event = message.event
                self = try .readEvent(event: .init(message: event), retryCount: event.retryCount)
            }else{
                self = .confirmation(subscriptionId: message.subscriptionConfirmation.subscriptionID)
            }
        }
    }
}

extension PersistentSubscriptionsClient.Read {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var message: UnderlyingMessage

        public init() {
            message = .init()
            message.bufferSize = 1000
            message.uuidOption.string = .init()
        }

        public func set(bufferSize: Int32) -> Self {
            message.bufferSize = bufferSize
            return self
        }

        public func set(uuidOption: UUID.Option) -> Self {
            switch uuidOption {
            case .string:
                message.uuidOption.string = .init()
            case .structured:
                message.uuidOption.structured = .init()
            }
            return self
        }

        public func build() -> UnderlyingMessage {
            message
        }
    }
}
