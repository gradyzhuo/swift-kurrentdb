//
//  PersistentSubscriptions.List.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPCSupport

extension PersistentSubscriptionsClient {
    
    public struct List: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_PersistentSubscriptions_ListReq>

        let options: Options

        public func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
            }
        }
    }
}

extension PersistentSubscriptionsClient.List {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_ListResp

        var subscriptions: [PersistentSubscriptionsClient.SubscriptionInfo]

        public init(from message: UnderlyingMessage) throws {
            subscriptions = message.subscriptions.map { .init(from: $0) }
        }
    }
}

extension PersistentSubscriptionsClient.List {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        var options: UnderlyingMessage

        init(options: UnderlyingMessage) {
            self.options = options
        }
        
        public static func listAllScriptions() -> Self {
            var options = UnderlyingMessage()
            options.listAllSubscriptions = .init()
            return .init(options: options)
        }

        @discardableResult
        public static func listForStream(_ selection: Selector<Stream.Identifier>) throws -> Self {
            var options = UnderlyingMessage()
            switch selection {
            case .all:
                options.listForStream.all = .init()
            case .specified(let streamIdentifier):
                options.listForStream.stream = try streamIdentifier.build()
            }
            return .init(options: options)
        }

        public func build() -> UnderlyingMessage {
            return options
        }
    }
}
