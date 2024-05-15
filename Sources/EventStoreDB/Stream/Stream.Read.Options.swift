//
//  Stream.Read.Options.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCEncapsulates

extension StreamClient.Read {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadReq.Options

        public var options: UnderlyingMessage

        public init() {
            options = .init()

            set(uuidOption: .string)
                .noFilter()
                .countBy(limit: .max)
        }

        public func build() -> UnderlyingMessage {
            options
        }

        @discardableResult
        public func noFilter() -> Self {
            options.noFilter = .init()
            return self
        }

        @discardableResult
        public func set(resolveLinks: Bool) -> Self {
            options.resolveLinks = resolveLinks
            return self
        }

        @discardableResult
        public func countBy(limit: UInt64) -> Self {
            options.count = limit
            return self
        }

        @discardableResult
        public func countBySubscription() -> Self {
            options.subscription = .init()
            return self
        }

        @discardableResult
        public func set(uuidOption: StreamClient.Read.UUIDOption) -> Self {
            uuidOption.build(options: &options)
            return self
        }

        @discardableResult
        public func set(compatibility: UInt32) -> Self {
            StreamClient.Read.ControlOption.compatibility(compatibility)
                .build(options: &options)
            return self
        }
    }
}
