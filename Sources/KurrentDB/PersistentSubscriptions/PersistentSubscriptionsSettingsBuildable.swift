//
//  PersistentSubscriptionsSettingsBuildable.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation
import GRPCEncapsulates

/// Protocol for option types that carry configurable persistent subscription settings.
public protocol PersistentSubscriptionsSettingsBuildable: Buildable {
    associatedtype SettingsType
    /// Mutable settings that configure the persistent subscription operation.
    var settings: SettingsType { set get }
}
