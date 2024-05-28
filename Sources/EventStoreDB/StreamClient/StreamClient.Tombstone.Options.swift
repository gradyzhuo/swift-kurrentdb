//
//  StreamClient.Tombstone.Options.swift
//
//
//  Created by Grady Zhuo on 2023/11/2.
//

import Foundation
import GRPCEncapsulates

extension StreamClient.Tombstone {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_TombstoneReq.Options

        public private(set) var expectedRevision: Stream.RevisionRule = .streamExists

        public func build() -> UnderlyingMessage {
            .with {
                switch expectedRevision {
                case .any:
                    $0.any = .init()
                case .noStream:
                    $0.noStream = .init()
                case .streamExists:
                    $0.streamExists = .init()
                case let .revision(rev):
                    $0.revision = rev
                }
            }
        }

        @discardableResult
        public func revision(expected expectedRevision: Stream.RevisionRule) -> Self {
            withCopy { options in
                options.expectedRevision = expectedRevision
            }
        }
    }
}
