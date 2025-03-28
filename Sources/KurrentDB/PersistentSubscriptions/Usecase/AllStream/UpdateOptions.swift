//
//  UpdateOptions.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/28.
//

import GRPCEncapsulates

extension PersistentSubscriptions {
    public struct UpdateOptions: PersistentSubscriptionsCommonOptions {
        package typealias UnderlyingMessage = UnderlyingService.Method.Update.Input.Options

        internal var settings: PersistentSubscription.Settings

        public init() {
            self.settings = .init()
        }

        package func build() -> UnderlyingMessage {
            .with {
                $0.settings = .from(settings: settings)
            }
        }
    }
}
