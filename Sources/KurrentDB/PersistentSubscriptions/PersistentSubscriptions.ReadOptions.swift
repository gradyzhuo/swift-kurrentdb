//
//  ReadOptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/28.
//
import Foundation
import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct ReadOptions: EventStoreOptions {
        package typealias UnderlyingMessage = Read.UnderlyingRequest.Options

        public private(set) var bufferSize: Int32
        public private(set) var uuidOption: UUID.Option

        public init() {
            bufferSize = 1000
            uuidOption = .string
        }

        public func bufferSize(_ bufferSize: Int32) -> Self {
            withCopy { options in
                options.bufferSize = bufferSize
            }
        }

        public func uuidOption(_ uuidOption: UUID.Option) -> Self {
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


//MARK: - Deprecated
extension PersistentSubscriptions.ReadOptions {
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
}
