//
//  PersistentSubscriptionsClient.Read.swift
//
//
//  Created by Grady Zhuo on 2023/12/8.
//

import Foundation
import GRPCEncapsulates

extension PersistentSubscriptionsClient {
    public struct Read: StreamStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReadReq>

        public let streamSelection: Selector<Stream.Identifier>
        public let groupName: String
        public let options: Options

        package func build() throws -> [Request.UnderlyingMessage] {
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

extension ReadEvent {
    package init(message: EventStore_Client_PersistentSubscriptions_ReadResp.ReadEvent) throws {
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
            } else {
                self = .confirmation(subscriptionId: message.subscriptionConfirmation.subscriptionID)
            }
        }
    }
}

extension PersistentSubscriptionsClient.Read {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

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
