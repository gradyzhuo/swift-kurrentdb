//
//  MonitoringClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import Foundation
import KurrentCore
import GRPCCore
import GRPCNIOTransportHTTP2Posix
import GRPCEncapsulates

public typealias UnderlyingService = EventStore_Client_Monitoring_Monitoring

public struct Service: GRPCConcreteClient {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias UnderlyingClient = UnderlyingService.Client<Transport>
    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults){
        self.settings = settings
        self.callOptions = callOptions
    }
}

extension Service {
    package func stats(useMetadata: Bool = false, refreshTimePeriodInMs: UInt64 = 10000) async throws -> Stats.Responses {
        let usecase = Stats(useMetadata: useMetadata, refreshTimePeriodInMs: refreshTimePeriodInMs)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
