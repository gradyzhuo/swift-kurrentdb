import Foundation
import GRPCEncapsulates

extension Gossip {
    public struct MemberInfo: GRPCResponse {
        package typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo

        public let instanceId: UUID
        public let timeStamp: TimeInterval
        public let state: VNodeState
        public let isAlive: Bool
        public let httpEndPoint: Endpoint

        package init(from message: UnderlyingMessage) throws(KurrentError) {
            guard let uuid = message.instanceID.toUUID() else {
                throw .initializationError(reason: "MemberInfo can't convert an UUID from message.instanceID: \(message.instanceID)")
            }
            instanceId = uuid
            timeStamp = TimeInterval(message.timeStamp)
            state = .init(from: message.state)
            isAlive = message.isAlive
            httpEndPoint = .init(host: message.httpEndPoint.address, port: message.httpEndPoint.port)
        }
    }
}
