//
//  Gossip.Read.swift
//
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct Read: UnaryUnary {
    public typealias Client = Gossip.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Read.Output
    public typealias Response = [Read.MemberInfo]
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.read(request: request, options: callOptions){
            try $0.message.members.map {
                try .init(from: $0)
            }
        }
    }
}

extension Read {
    public struct MemberInfo: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo

        public let instanceId: UUID
        public let timeStamp: TimeInterval
        public let state: UnderlyingMessage.VNodeState
        public let isAlive: Bool
        public let httpEndPoint: ClientSettings.Endpoint

        public init(from message: UnderlyingMessage) throws {
            guard let uuid = message.instanceID.toUUID() else {
                throw ClientError.readResponseError(message: "The instance id not found.")
            }
            instanceId = uuid
            timeStamp = TimeInterval(message.timeStamp)
            state = message.state
            isAlive = message.isAlive
            httpEndPoint = .init(host: message.httpEndPoint.address, port: message.httpEndPoint.port)
        }
    }
}
