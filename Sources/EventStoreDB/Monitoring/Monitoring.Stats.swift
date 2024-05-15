//
//  Monitoring.Stats.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import GRPCEncapsulates

extension MonitoringClient {
    public struct Stats: UnaryStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Monitoring_StatsReq>

        let useMetadata: Bool
        let refreshTimePeriodInMs: UInt64

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.useMetadata = useMetadata
                $0.refreshTimePeriodInMs = refreshTimePeriodInMs
            }
        }
    }
}

extension MonitoringClient.Stats {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Monitoring_StatsResp

        var stats: [String: String]

        public init(from message: UnderlyingMessage) throws {
            stats = message.stats
        }
    }
}
