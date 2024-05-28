//
//  StreamClient.Append.Options.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCEncapsulates

extension StreamClient.Append {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        public private(set) var expectedRevision: Stream.RevisionRule

        public init() {
            expectedRevision = .any
        }

        public func revision(expected: Stream.RevisionRule) -> Self {
            withCopy { options in
                options.expectedRevision = expected
            }
        }

        package func build() -> UnderlyingMessage {
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
    }
}
