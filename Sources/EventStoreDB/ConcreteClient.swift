//
//  EventStoreClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPC
import SwiftProtobuf

public protocol ConcreteClient {
    associatedtype UnderlyingClient: EventStoreGRPCClient

    var channel: GRPCChannel { get }
    var callOptions: CallOptions { set get }
}

extension ConcreteClient {
    internal var underlyingClient: UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
}
