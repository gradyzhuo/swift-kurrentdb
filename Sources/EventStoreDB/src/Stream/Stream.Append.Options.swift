//
//  Stream.Append.Options.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCSupport

extension StreamClient.Append {
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options

        public var options: UnderlyingMessage = .init()

        public var expectedRevision: StreamClient.Revision {
            didSet {
                switch expectedRevision {
                case .any:
                    options.any = .init()
                case .noStream:
                    options.noStream = .init()
                case .streamExists:
                    options.streamExists = .init()
                case let .revision(rev):
                    options.revision = rev
                }
            }
        }

        public init() {
            expectedRevision = .any
        }

        public func build() -> UnderlyingMessage {
            options
        }
    }
}
