//
//  PersistentSubscriptions.ReplayParkedOptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/28.
//

import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct ReplayParkedOptions: CommandOptions {
        public enum StopAtOption {
            case position(position: Int64)
            case noLimit
        }

        package typealias UnderlyingMessage = UnderlyingService.Method.ReplayParked.Input.Options

        var message: UnderlyingMessage

        public init() {
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

        package func build() -> UnderlyingMessage {
            message
        }
    }
}
