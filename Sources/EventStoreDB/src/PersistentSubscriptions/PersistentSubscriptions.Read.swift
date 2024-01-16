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

        let streamSelection: StreamSelection
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
                },
            ]
        } // End of build
    }
}

extension PersistentSubscriptionsClient.Read {
    public struct Result {
        public let event: ReadEvent
        let sender: PersistentSubscriptionsClient
        public let subscriptionId: String

        public func ack() async throws {
            try await sender.ack(eventIds: [event.event.id], subscriptionId: subscriptionId)
        }
    }
}

extension PersistentSubscriptionsClient.Read {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ReadResp

        let message: UnderlyingMessage
//
//        public let event: ReadEvent
//        var sender: PersistentSubscriptions?
//        var subscriptionId: String?
//
        public init(from message: UnderlyingMessage) {
            self.message = message
//            self.event = try .init(message: message.event)
        }

//        public func ack() async throws {
//            let ackRequest: Request.UnderlyingMessage = .with{
//                $0.ack = .with{
//                    $0.id = subscriptionId?.data(using: .utf8) ?? Data()
//                    $0.ids = [self.event.event.id.toEventStoreUUID()]
//                }
//            }
//
//            if let ackResponses = self.sender?.underlyingClient.read([ackRequest]){
//                for try await i in ackResponses{
//                    print("ack LLLLL:", i)
//                }
//            }
//
//
//        }

        public func nack() {}
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
