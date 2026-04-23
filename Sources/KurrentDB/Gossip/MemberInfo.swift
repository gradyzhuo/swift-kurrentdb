import Foundation
import GRPCEncapsulates

extension Gossip {
    /// Snapshot of a single cluster member as reported by the gossip protocol.
    public struct MemberInfo: GRPCResponse {
        package typealias UnderlyingMessage = EventStore_Client_Gossip_MemberInfo

        /// Unique identifier for this node instance.
        public let instanceId: UUID
        /// Timestamp of the gossip report, expressed as seconds since the Unix epoch.
        public let timeStamp: TimeInterval
        /// Current lifecycle state of this node.
        public let state: VNodeState
        /// Indicates whether this node is currently healthy and reachable.
        public let isAlive: Bool
        /// HTTP endpoint used to communicate with this node.
        public let httpEndPoint: Endpoint

        init(instanceId: UUID, timeStamp: TimeInterval, state: VNodeState, isAlive: Bool, httpEndPoint: Endpoint) {
            self.instanceId = instanceId
            self.timeStamp = timeStamp
            self.state = state
            self.isAlive = isAlive
            self.httpEndPoint = httpEndPoint
        }

        package init(from message: UnderlyingMessage) throws(KurrentError) {
            guard let uuid = message.instanceID.toUUID() else {
                throw .initializationError(reason: "MemberInfo can't convert an UUID from message.instanceID: \(message.instanceID)")
            }
            self.init(
                instanceId: uuid,
                timeStamp: TimeInterval(message.timeStamp),
                state: .init(from: message.state),
                isAlive: message.isAlive,
                httpEndPoint: .init(host: message.httpEndPoint.address, port: message.httpEndPoint.port)
            )
        }
    }
}
