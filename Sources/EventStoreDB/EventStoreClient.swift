//
//  EventStoreClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPC
import SwiftProtobuf

public protocol EventStoreClient {
    associatedtype UnderlyingClient: GRPCClient

    var clientSettings: ClientSettings { get set }
    var channel: GRPCChannel { get }

    func makeClient(callOptions: CallOptions) throws -> UnderlyingClient
}

extension EventStoreClient {
    public var underlyingClient: UnderlyingClient {
        get throws {
            let options = try clientSettings.makeCallOptions()
            return try makeClient(callOptions: options)
        }
    }
}
