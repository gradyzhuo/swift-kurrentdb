//
//  MonitoringClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPC
import GRPCEncapsulates

public struct MonitoringClient: GRPCConcreteClient {
    package typealias UnderlyingClient = EventStore_Client_Monitoring_MonitoringAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions

    public init(channel: GRPCChannel, callOptions: CallOptions) throws {
        self.channel = channel
        self.callOptions = callOptions
    }

    package func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        .init(channel: channel, defaultCallOptions: callOptions)
    }

    package func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws -> AsyncStream<Stats.Response> {
        let handler = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        let request = try handler.build()
        let responses = underlyingClient.stats(request)

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
