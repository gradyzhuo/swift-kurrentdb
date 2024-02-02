//
//  Stream.Delete.Options.swift
//
//
//  Created by Grady Zhuo on 2023/10/31.
//

import Foundation
import GRPCSupport

extension StreamClient.Delete {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_DeleteReq.Options

        var options: UnderlyingMessage

        public init() {
            options = .with {
                $0.noStream = .init()
            }
        }

        public func build() -> UnderlyingMessage {
            options
        }

        @discardableResult
        public func expected(revision: StreamClient.Revision) -> Self {
            switch revision {
            case .any:
                options.any = .init()
            case .noStream:
                options.noStream = .init()
            case .streamExists:
                options.streamExists = .init()
            case let .revision(rev):
                options.revision = rev
            }
            return self
        }
    }
}
