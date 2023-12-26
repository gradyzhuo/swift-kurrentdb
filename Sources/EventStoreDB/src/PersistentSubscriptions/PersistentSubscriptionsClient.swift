//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import GRPC
import GRPCSupport


@available(macOS 13.0, *)
public struct PersistentSubscriptionsClient: EventStoreClient {
    
    public typealias UnderlyingClient = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient
    
    public var clientSettings: ClientSettings
    public var channel: GRPCChannel
    var streamSelection: StreamSelection
    var groupName: String

    public init(selection: StreamSelection, groupName: String, settings: ClientSettings = EventStoreDB.shared.settings) throws{
        self.clientSettings = settings
        self.channel = try GRPCChannelPool.with(settings: clientSettings)
        self.streamSelection = selection
        self.groupName = groupName
    }
    
    
    public func makeClient(callOptions: CallOptions) throws -> UnderlyingClient {
        return .init(channel: channel, defaultCallOptions: callOptions)
    }
    
}


@available(macOS 13.0, *)
extension PersistentSubscriptionsClient{
    
    //MARK: - Create Action
    public static func createOn(streamSelection selection: Create.StreamSelection, groupName: String, options: Create.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> Self{
        
        let channel = try GRPCChannelPool.with(settings: settings)
        var underlyingClient: UnderlyingClient = .init(channel: channel)
        try underlyingClient.configure(by: settings)
        
        let handler: Create = .init(streamSelection: selection, groupName: groupName, options: options)
        let request = try handler.build()
        
        try await handler.handle(response: underlyingClient.create(request))
        
        return switch selection{
        case .all:
            try .init(selection: .all, groupName: groupName, settings: settings)
        case .specified(let streamIdentifier, _):
            try .init(selection: .specified(streamIdentifier: streamIdentifier), groupName: groupName, settings: settings)
        }
        
    }
    
    public static func createOn(streamSelection selection: Create.StreamSelection, groupName: String, settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: Create.Options)->Create.Options) async throws -> Self{
        
        let options = configure(.init())
        return try await createOn(streamSelection: selection, groupName: groupName, options: options, settings: settings)
    }
    
    
    
    
    //MARK: - Update Action
    
    private func update(streamSelection selection: Update.StreamSelection, options: Update.Options) async throws {
        
        let handler = Update(streamSelection: selection, groupName: groupName, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
        
    }
    
    private func update(streamSelection selection: Update.StreamSelection, configure: (_ options: Update.Options)->Update.Options) async throws {
        
        let options = configure(.init())
        try await update(streamSelection: selection, options: options)
        
    }
    
    //MARK: - Delete Actions
    
    public static func deleteOn(streamSelection selection: StreamSelection, groupName: String, settings: ClientSettings = EventStoreDB.shared.settings) async throws {
        
        let channel = try GRPCChannelPool.with(settings: settings)
        var underlyingClient: UnderlyingClient = .init(channel: channel)
        try underlyingClient.configure(by: settings)
        
        let handler = Delete(streamSelection: selection, groupName: groupName)
        let request = try handler.build()
        
        try await handler.handle(response: underlyingClient.delete(request))
    }
    
    //MARK: - Read Actions
    
    public func read(options: Read.Options) async throws -> AsyncStream<Read.Result> {
        
        let handler = Read.init(streamSelection: self.streamSelection, groupName: groupName, options: options)
        
        let requests = try handler.build()
        let responses =  try underlyingClient.read(requests)
        
//        let try await responses.first { resp in
//            guard let content = resp.content else{
//                return false
//            }
//            switch content {
//                
//            case .event(_):
//                return false
//            case .subscriptionConfirmation(_):
//                return true
//            }
//        }
        
        return .init { continuation in
            
            Task {
                
                var iterator = responses.makeAsyncIterator()
                guard let response = try await iterator.next() else {
                    continuation.finish()
                    return
                }
                
                let streamIdentifier = switch streamSelection {
                case .all:
                    "$all"
                case .specified(let streamIdentifier):
                    streamIdentifier.name
                }
                
                let subscriptionId: String
                if case let .subscriptionConfirmation(confirmation) = response.content! {
                    subscriptionId = confirmation.subscriptionID
                }else{
                    print("subscriptionID is not equal to stream identifier and group name.")
                    subscriptionId = "\(streamIdentifier)::\(groupName)"
                }
                
                while let underlyingResponse = try await iterator.next() {
                    let response = try handler.handle(response: underlyingResponse)
                    
                    let event = try ReadEvent.init(message: response.message.event)
                    
                    let result = Read.Result(
                        event: event,
                        sender: self,
                        subscriptionId: subscriptionId)
                    
                    continuation.yield(result)
                }
                
                continuation.finish()
                
            }
        }
        
    }
    
    // MARK: - Ack Action
    public func ack(eventIds: [UUID], subscriptionId: String? = nil) async throws {
        
        let streamIdentifier = switch streamSelection {
        case .all:
            "$all"
        case .specified(let streamIdentifier):
            streamIdentifier.name
        }
        
        let subscriptionId = subscriptionId ?? "\(streamIdentifier)::\(groupName)"
        
        let handler: Ack = .init(subscriptionId: subscriptionId, eventIds: eventIds)
        
        let requests = try handler.build()
        
        let rs = try underlyingClient.read(requests)
        
        for try await i in rs{
            print("ack LLLLL:", i)
        }
        
    }
    
    public func ack(eventIds: UUID ..., subscriptionId: String? = nil) async throws {
        try await self.ack(eventIds: eventIds, subscriptionId: subscriptionId)
    }
    
    public func ack(readEvents: [ReadEvent], subscriptionId: String? = nil) async throws {
        try await self.ack(eventIds: readEvents.map{ $0.event.id },
                           subscriptionId: subscriptionId)
    }
    
    public func ack(readEvents: ReadEvent ..., subscriptionId: String? = nil) async throws {
        try await self.ack(readEvents: readEvents, subscriptionId: subscriptionId)
    }
    
    
    // MARK: - Nack
    public func nack(subscriptionId: String, eventIds: [UUID], action: Nack.Action, reason: String) async throws {
        let handler: Nack = .init(subscriptionId: subscriptionId, eventIds: eventIds, action: action, reason: reason)
        
        let requests = try handler.build()
        print(requests)
        
        let rs  = try underlyingClient.read(requests)
        
        for try await i in rs{
            print("nack LLLLL:", i)
        }
        
    }
    
    // MARK: - GetInfo Action
    
    public func getInfo() async throws -> SubscriptionInfo{
        let handler = GetInfo(streamSelection: self.streamSelection, groupName: self.groupName)
        let request = try handler.build()
        let response = try await handler.handle(response: self.underlyingClient.getInfo(request))
        return response.subscriptionInfo
    }
    
    //MARK: - ReplayParked Action
    public func replayParkedMessage(options: ReplayParked.Options) async throws {
        let handler = ReplayParked(streamSelection: self.streamSelection, groupName: self.groupName, options: options)
        let request = try handler.build()
        let _ = try await handler.handle(response: self.underlyingClient.replayParked(request))
    }
    
    public func replayParkedMessage(configure: (_ options: ReplayParked.Options) -> ReplayParked.Options) async throws {
        try await replayParkedMessage(options: configure(.init()))
    }
    
    //MARK: - List Action
    
    public static func list(options: List.Options, settings: ClientSettings = EventStoreDB.shared.settings) async throws -> [SubscriptionInfo]{
        let channel = try GRPCChannelPool.with(settings: settings)
        
        var client = UnderlyingClient(channel: channel)
        try client.configure(by: settings)
        
        let handler = List(options: options)
        let request = try handler.build()
        let response = try await handler.handle(response: client.list(request))
        return response.subscriptions
    }
    
    public static func list(settings: ClientSettings = EventStoreDB.shared.settings, configure: (_ options: List.Options) -> List.Options) async throws -> [SubscriptionInfo]{
        return try await list(options: configure(.init()), settings: settings)
    }
    
    //MARK: - Restart Subsystem Action
    
    public static func restartSubsystem(settings: ClientSettings = EventStoreDB.shared.settings) async throws{
        let channel = try GRPCChannelPool.with(settings: settings)
        var client = UnderlyingClient(channel: channel)
        try client.configure(by: settings)
        
        let handler = RestartSubsystem()
        try await handler.handle(response: client.restartSubsystem(handler.build()))
    }
}



@available(macOS 13.0, *)
extension PersistentSubscriptionsClient {
    
    public enum StreamSelection {
        case all
        case specified(streamIdentifier: StreamClient.Identifier)
    }
    
    public enum TimeSpan{
        case ticks(Int64)
        case ms(Int32)
    }
    
}

@available(macOS 13.0, *)
extension PersistentSubscriptionsClient{
    
    public struct Measurement {
        public let key: String
        public let value: Int64
    }
    
    public struct ConnectionInfo {
        public let `from`: String
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
        
        init(from message: UnderlyingMessage){
            
            let connections: [PersistentSubscriptionsClient.ConnectionInfo] = message.connections.map{
                .init(
                    from: $0.from,
                    username: $0.username,
                    averageItemsPerSecond: $0.averageItemsPerSecond,
                    totalItems: $0.totalItems,
                    countSinceLastMeasurement: $0.countSinceLastMeasurement,
                    obervedMeasurements: $0.observedMeasurements.map{
                        .init(key: $0.key, value: $0.value)
                    },
                    availableSlots: $0.availableSlots,
                    inFlightMessages: $0.inFlightMessages,
                    connectionName: $0.connectionName)
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
                parkedMessageCount: message.parkedMessageCount)
        }
    }
}
