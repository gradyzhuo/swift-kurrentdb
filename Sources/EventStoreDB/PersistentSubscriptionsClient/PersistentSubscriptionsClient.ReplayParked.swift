//
//  PersistentSubscriptionsClient.ReplayParked.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPCEncapsulates

extension PersistentSubscriptionsClient {
    public struct ReplayParked: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ReplayParkedReq>
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_ReplayParkedResp>

        let streamSelection: Selector<Stream.Identifier>
        let groupName: String
        let options: Options

        package func build() throws -> EventStore_Client_PersistentSubscriptions_ReplayParkedReq {
            try .with {
                $0.options = options.build()
                $0.options.groupName = groupName

                switch streamSelection {
                case .all:
                    $0.options.all = .init()
                case let .specified(streamIdentifier):
                    $0.options.streamIdentifier = try streamIdentifier.build()
                }
            }
        }
    }
}

extension PersistentSubscriptionsClient.ReplayParked {
    public struct Options: EventStoreOptions {
        public enum StopAtOption {
            case position(position: Int64)
            case noLimit
        }

        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        var message: UnderlyingMessage

        init() {
            message = .init()
            stop(at: .noLimit)
        }

        @discardableResult
        public func stop(at option: StopAtOption) -> Self {
            withCopy { options in
                switch option {
                case let .position(position):
                    options.message.stopAt = position
                case .noLimit:
                    options.message.noLimit = .init()
                }
            }
        }

        package func build() -> PersistentSubscriptionsClient.ReplayParked.Request.UnderlyingMessage.Options {
            message
        }
    }
}
