//
//  SubscriptionEventResult.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2026/4/23.
//


public protocol SubscriptionEventResult: Sendable {
    var revision: UInt64? { get }
    var position: StreamPosition? { get }
}
