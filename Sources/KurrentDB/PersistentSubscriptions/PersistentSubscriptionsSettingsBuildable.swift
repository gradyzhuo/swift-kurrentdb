//
//  PersistentSubscriptionsSettingsBuildable.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2024/3/22.
//

import Foundation
import GRPCEncapsulates

public protocol PersistentSubscriptionsSettingsBuildable: Buildable {
    associatedtype SettingsType
    var settings: SettingsType { set get }
}
