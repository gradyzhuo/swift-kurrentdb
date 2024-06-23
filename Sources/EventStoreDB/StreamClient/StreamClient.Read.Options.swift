//
//  StreamClient.Read.Options.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCEncapsulates

extension StreamClient.Read {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadReq.Options

        public private(set) var resolveLinks: Bool = false
        public private(set) var limit: UInt64 = .max
        public private(set) var uuidOption: Stream.UUIDOption = .string

        package func build() -> UnderlyingMessage {
            .with {
                $0.noFilter = .init()

                switch uuidOption {
                case .structured:
                    $0.uuidOption.structured = .init()
                case .string:
                    $0.uuidOption.string = .init()
                }

                $0.resolveLinks = resolveLinks
                $0.count = limit
            }
        }

        @discardableResult
        public func set(resolveLinks: Bool) -> Self {
            withCopy { options in
                options.resolveLinks = resolveLinks
            }
        }

        @discardableResult
        public func set(limit: UInt64) -> Self {
            withCopy { options in
                options.limit = limit
            }
        }

        @discardableResult
        public func set(uuidOption: Stream.UUIDOption) -> Self {
            withCopy { options in
                options.uuidOption = uuidOption
            }
        }
    }
}
