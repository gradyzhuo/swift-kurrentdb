//
//  OperationsClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPC
import GRPCEncapsulates

public struct OperationsClient: ConcreteClient {
    public typealias UnderlyingClient = EventStore_Client_Operations_OperationsAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions

    internal var underlyingClient: UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
    
    init(channel: GRPCChannel, callOptions: CallOptions) {
        self.channel = channel
        self.callOptions = callOptions
    }
}

extension OperationsClient {
    public func startScavenge(threadCount: Int32, startFromChunk: Int32) async throws -> OperationsClient.ScavengeResponse {

        let handler = OperationsClient.StartScavenge(threadCount: threadCount, startFromChunk: startFromChunk)
        let request = try handler.build()
        
        return try await handler.handle(response: underlyingClient.startScavenge(request))
        
    }
    
    public func shutdown(){
        
    }
    
}
