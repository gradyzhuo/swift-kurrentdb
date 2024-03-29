//
//  PersistentSubscriptionsClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPC
import GRPCSupport

public struct PersistentSubscriptionsClient: ConcreteClient {
    public typealias UnderlyingClient = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions
    
    public init(channel: GRPCChannel, callOptions: CallOptions) {
        self.channel = channel
        self.callOptions = callOptions
    }

}


extension PersistentSubscriptionsClient {
    
    public enum StreamSelection {
        case all(position: Cursor<StreamClient.Read.Position>, filterOption: StreamClient.FilterOption? = nil)
        case specified(identifier: Stream.Identifier, revision: Cursor<UInt64>)
        
        public static func specified(identifier: Stream.Identifier)->Self{
            return .specified(identifier: identifier, revision: .end)
        }

        public static func specified(streamName: String, revision: Cursor<UInt64> = .end)->Self{
            return .specified(identifier: .init(name: streamName), revision: .end)
        }
    }
    
    public enum SystemConsumerStrategy: RawRepresentable {
        public typealias RawValue = String
        
        /// Distributes events to a single client until the bufferSize is reached.
        /// After which the next client is selected in a round robin style,
        /// and the process is repeated.
        case dispatchToSingle

        /// Distributes events to all clients evenly. If the client buffer-size
        /// is reached the client is ignored until events are
        /// acknowledged/not acknowledged.
        case roundRobin

        /// For use with an indexing projection such as the system $by_category
        /// projection. Event Store inspects event for its source stream id,
        /// hashing the id to one of 1024 buckets assigned to individual clients.
        /// When a client disconnects it's buckets are assigned to other clients.
        /// When a client connects, it is assigned some of the existing buckets.
        /// This naively attempts to maintain a balanced workload.
        /// The main aim of this strategy is to decrease the likelihood of
        /// concurrency and ordering issues while maintaining load balancing.
        /// This is not a guarantee, and you should handle the usual ordering
        /// and concurrency issues.
        case pinned

        case pinnedByCorrelation

        case custom(String)
        
        public var rawValue: String {
            return switch self {
            case .dispatchToSingle:
                "DispatchToSingle"
            case .roundRobin:
                "RoundRobin"
            case .pinned:
                "Pinned"
            case .pinnedByCorrelation:
                "PinnedByCorrelation"
            case .custom(let value):
                value
            }
        }
        public init?(rawValue: String) {
            switch rawValue {
            case Self.dispatchToSingle.rawValue:
                self = .dispatchToSingle
            case Self.roundRobin.rawValue:
                self = .roundRobin
            case Self.pinned.rawValue:
                self = .pinned
            case Self.pinnedByCorrelation.rawValue:
                self = .pinnedByCorrelation
            default:
                self = .custom(rawValue)
            }
        }
    }
}

extension PersistentSubscriptionsClient {
    // MARK: - Create Action
    
    public func createToStream(streamName: String, groupName: String, options: Create.ToStream.Options) async throws{
        
        let handler: Create.ToStream = .init(streamIdentifier: .init(name: streamName), groupName: groupName, options: options)
        
        let request = try handler.build()

        try await handler.handle(response: underlyingClient.create(request))
    }
    
    public func createToAll(groupName: String, options: PersistentSubscriptionsClient.Create.ToAll.Options) async throws {
        let handler: PersistentSubscriptionsClient.Create.ToAll = .init(groupName: groupName, options: options)
        
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.create(request))
        
    }


    // MARK: - Update Action
    
    public func updateToStream(identifier: Stream.Identifier, groupName: String, options: Update.ToStream.Options) async throws {
        let handler = Update.ToStream(streamIdentifier: identifier, groupName: groupName, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
    }
    
    public func updateToAll(identifier: Stream.Identifier, groupName: String, options: Update.ToAll.Options) async throws {
        let handler = Update.ToAll(groupName: groupName, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
    }

    // MARK: - Delete Actions

    public func deleteOn(stream: Selector<Stream.Identifier>, groupName: String) async throws {

        let handler = Delete(streamSelection: stream, groupName: groupName)
        let request = try handler.build()

        try await handler.handle(response: underlyingClient.delete(request))
        
    }

    // MARK: - Read Actions
    
    public func subscribeTo(_ streamSelection: Selector<Stream.Identifier>, groupName: String, options: Read.Options) async throws -> Subscriber {
        
        
        let handler = Read(streamSelection: streamSelection, groupName: groupName, options: options)
        let requests = try handler.build()
        
        let getSubscriptionCall = underlyingClient.makeReadCall()
        try await getSubscriptionCall.requestStream.send(requests)

        return try await .init(readCall: getSubscriptionCall)
    }


    // MARK: - GetInfo Action

    public func getInfo(stream streamSelection: Selector<Stream.Identifier>, groupName: String) async throws -> SubscriptionInfo {
        
        let handler = GetInfo(streamSelection: streamSelection, groupName: groupName)
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.getInfo(request))
        
        return response.subscriptionInfo
    }

    // MARK: - ReplayParked Action

    public func replayParkedMessages(stream streamSelection: Selector<Stream.Identifier>, groupName: String, options: ReplayParked.Options) async throws {
        
        let handler = ReplayParked(streamSelection: streamSelection, groupName: groupName, options: options)
        let request = try handler.build()
        
        try await handler.handle(response: underlyingClient.replayParked(request))
        
    }

    public func replayParkedMessages(stream streamSelection: Selector<Stream.Identifier>, groupName: String, configure: (_ options: ReplayParked.Options) -> ReplayParked.Options) async throws {
        try await replayParkedMessages(stream: streamSelection, groupName:groupName, options: configure(.init()))
    }

    // MARK: - List Action

    public func list(stream: Selector<Stream.Identifier>) async throws -> [SubscriptionInfo] {
        
        let options = try List.Options.listForStream(stream)
        
        let handler = List(options: options)
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.list(request))
        return response.subscriptions
    }

    // MARK: - Restart Subsystem Action

    public func restartSubsystem() async throws {
        let handler = RestartSubsystem()
        try await handler.handle(response: underlyingClient.restartSubsystem(handler.build(), callOptions: callOptions))
    }
}

extension PersistentSubscriptionsClient {
    public struct Measurement {
        public let key: String
        public let value: Int64
    }

    public struct ConnectionInfo {
        public let from: String
        public let username: String
        public let averageItemsPerSecond: Int32
        public let totalItems: Int64
        public let countSinceLastMeasurement: Int64
        public let obervedMeasurements: [Measurement]
        public let availableSlots: Int32
        public let inFlightMessages: Int32
        public let connectionName: String
    }

    public struct SubscriptionInfo: GRPCBridge {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_SubscriptionInfo
        public let eventSource: String
        public let groupName: String
        public let status: String
        public let connections: [ConnectionInfo]
        public let averagePerSecond: Int32
        public let totalItems: Int64
        public let countSinceLastMeasurement: Int64
        public let lastCheckpointedEventPosition: String
        public let lastKnownEventPosition: String
        public let resolveLinkTos: Bool
        public let startFrom: String
        public let messageTimeoutMilliseconds: Int32
        public let extraStatistics: Bool
        public let maxRetryCount: Int32
        public let liveBufferSize: Int32
        public let bufferSize: Int32
        public let readBatchSize: Int32
        public let checkPointAfterMilliseconds: Int32
        public let minCheckPointCount: Int32
        public let maxCheckPointCount: Int32
        public let readBufferCount: Int32
        public let liveBufferCount: Int64
        public let retryBufferCount: Int32
        public let totalInFlightMessages: Int32
        public let outstandingMessageCount: Int32
        public let namedConsumerStrategy: String
        public let maxSubscriberCount: Int32
        public let parkedMessageCount: Int64

        init(eventSource: String, groupName: String, status: String, connections: [ConnectionInfo], averagePerSecond: Int32, totalItems: Int64, countSinceLastMeasurement: Int64, lastCheckpointedEventPosition: String, lastKnownEventPosition: String, resolveLinkTos: Bool, startFrom: String, messageTimeoutMilliseconds: Int32, extraStatistics: Bool, maxRetryCount: Int32, liveBufferSize: Int32, bufferSize: Int32, readBatchSize: Int32, checkPointAfterMilliseconds: Int32, minCheckPointCount: Int32, maxCheckPointCount: Int32, readBufferCount: Int32, liveBufferCount: Int64, retryBufferCount: Int32, totalInFlightMessages: Int32, outstandingMessageCount: Int32, namedConsumerStrategy: String, maxSubscriberCount: Int32, parkedMessageCount: Int64) {
            self.eventSource = eventSource
            self.groupName = groupName
            self.status = status
            self.connections = connections
            self.averagePerSecond = averagePerSecond
            self.totalItems = totalItems
            self.countSinceLastMeasurement = countSinceLastMeasurement
            self.lastCheckpointedEventPosition = lastCheckpointedEventPosition
            self.lastKnownEventPosition = lastKnownEventPosition
            self.resolveLinkTos = resolveLinkTos
            self.startFrom = startFrom
            self.messageTimeoutMilliseconds = messageTimeoutMilliseconds
            self.extraStatistics = extraStatistics
            self.maxRetryCount = maxRetryCount
            self.liveBufferSize = liveBufferSize
            self.bufferSize = bufferSize
            self.readBatchSize = readBatchSize
            self.checkPointAfterMilliseconds = checkPointAfterMilliseconds
            self.minCheckPointCount = minCheckPointCount
            self.maxCheckPointCount = maxCheckPointCount
            self.readBufferCount = readBufferCount
            self.liveBufferCount = liveBufferCount
            self.retryBufferCount = retryBufferCount
            self.totalInFlightMessages = totalInFlightMessages
            self.outstandingMessageCount = outstandingMessageCount
            self.namedConsumerStrategy = namedConsumerStrategy
            self.maxSubscriberCount = maxSubscriberCount
            self.parkedMessageCount = parkedMessageCount
        }

        init(from message: UnderlyingMessage) {
            let connections: [PersistentSubscriptionsClient.ConnectionInfo] = message.connections.map {
                .init(
                    from: $0.from,
                    username: $0.username,
                    averageItemsPerSecond: $0.averageItemsPerSecond,
                    totalItems: $0.totalItems,
                    countSinceLastMeasurement: $0.countSinceLastMeasurement,
                    obervedMeasurements: $0.observedMeasurements.map {
                        .init(key: $0.key, value: $0.value)
                    },
                    availableSlots: $0.availableSlots,
                    inFlightMessages: $0.inFlightMessages,
                    connectionName: $0.connectionName
                )
            }

            self.init(
                eventSource: message.eventSource,
                groupName: message.groupName,
                status: message.status,
                connections: connections,
                averagePerSecond: message.averagePerSecond,
                totalItems: message.totalItems,
                countSinceLastMeasurement: message.countSinceLastMeasurement,
                lastCheckpointedEventPosition: message.lastCheckpointedEventPosition,
                lastKnownEventPosition: message.lastKnownEventPosition,
                resolveLinkTos: message.resolveLinkTos,
                startFrom: message.startFrom,
                messageTimeoutMilliseconds: message.messageTimeoutMilliseconds,
                extraStatistics: message.extraStatistics,
                maxRetryCount: message.maxRetryCount,
                liveBufferSize: message.liveBufferSize,
                bufferSize: message.bufferSize,
                readBatchSize: message.readBatchSize,
                checkPointAfterMilliseconds: message.checkPointAfterMilliseconds,
                minCheckPointCount: message.minCheckPointCount,
                maxCheckPointCount: message.maxCheckPointCount,
                readBufferCount: message.readBufferCount,
                liveBufferCount: message.liveBufferCount,
                retryBufferCount: message.retryBufferCount,
                totalInFlightMessages: message.totalInFlightMessages,
                outstandingMessageCount: message.outstandingMessagesCount,
                namedConsumerStrategy: message.namedConsumerStrategy,
                maxSubscriberCount: message.maxSubscriberCount,
                parkedMessageCount: message.parkedMessageCount
            )
        }
    }
}
