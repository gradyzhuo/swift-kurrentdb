//
//  MonitoringClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPC
import GRPCSupport

public struct MonitoringClient: EventStoreClient {
    public typealias UnderlyingClient = EventStore_Client_Monitoring_MonitoringAsyncClient

    public var clientSettings: ClientSettings
    public var channel: GRPCChannel

    public init(settings: ClientSettings = EventStoreDB.shared.settings) throws {
        clientSettings = settings
        channel = try GRPCChannelPool.with(settings: settings)
    }

    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        .init(channel: channel, defaultCallOptions: callOptions)
    }

    public func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws -> AsyncStream<Stats.Response> {
        let handler = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        let request = try handler.build()
        let responses = try underlyingClient.stats(request)

        return .init { continuation in
            Task {
                for try await response in responses {
                    try continuation.yield(.init(from: response))
                }
                continuation.finish()
            }
        }
    }
}
