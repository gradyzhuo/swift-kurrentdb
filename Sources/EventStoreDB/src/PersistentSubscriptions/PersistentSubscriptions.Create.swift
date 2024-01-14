//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/7.
//

import Foundation
import GRPCSupport


extension PersistentSubscriptionsClient {
    
    public struct Create: UnaryUnary{
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_CreateResp>
        
        var streamSelection: StreamSelection
        var groupName: String
        var options: Options

        
        public func build() throws -> Request.UnderlyingMessage {
            return try .with{
                $0.options = options.build()
                try streamSelection.build(options: &$0.options)
            }
        }
        
    }
    
}


extension PersistentSubscriptionsClient.Create {
    
    public struct Request: GRPCRequest {
        public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_CreateReq
        
        
    }
    
    public final class Options: EventStoreOptions {

        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        public var options: UnderlyingMessage
        
        public init() {
            self.options = .with{
                $0.settings = .init()
            }
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        
        @discardableResult
        public func set(resolveLinks: Bool)->Self {
            options.settings.resolveLinks = resolveLinks
            return self
        }
        
        @discardableResult
        public func set(maxRetryCount: Int32)->Self {
            options.settings.maxRetryCount = maxRetryCount
            return self
        }
        
        @discardableResult
        public func set(minCheckpointCount: Int32)->Self {
            options.settings.minCheckpointCount = minCheckpointCount
            return self
        }
        
        @discardableResult
        public func set(maxCheckpointCount: Int32)->Self {
            options.settings.maxCheckpointCount = maxCheckpointCount
            return self
        }
        
        @discardableResult
        public func set(maxSubscriberCount: Int32)->Self {
            options.settings.maxSubscriberCount = maxSubscriberCount
            return self
        }
        
        @discardableResult
        public func set(liveBufferSize: Int32)->Self {
            options.settings.liveBufferSize = liveBufferSize
            return self
        }
        
        @discardableResult
        public func set(readBatchSize: Int32)->Self {
            options.settings.readBatchSize = readBatchSize
            return self
        }
        
        @discardableResult
        public func set(historyBufferSize: Int32)->Self {
            options.settings.historyBufferSize = historyBufferSize
            return self
        }
        
        @discardableResult
        public func set(consumerStrategy: String)->Self {
            options.settings.consumerStrategy = consumerStrategy
            return self
        }
        
        @discardableResult
        public func setMessageTimeout(_ timeout: PersistentSubscriptionsClient.TimeSpan)->Self {
            switch timeout {
            case .ticks(let messageTimeoutTicks):
                options.settings.messageTimeoutTicks = messageTimeoutTicks
            case .ms(let messageTimeoutMs):
                options.settings.messageTimeoutMs = messageTimeoutMs
            }
            return self
        }
        
        @discardableResult
        public func setCheckpoint(after span: PersistentSubscriptionsClient.TimeSpan)->Self {
            switch span {
            case .ticks(let checkpointAfterTicks):
                options.settings.checkpointAfterTicks = checkpointAfterTicks
            case .ms(let checkpointAfterMs):
                options.settings.checkpointAfterMs = checkpointAfterMs
            }
            return self
        }
        
    }
}

// MARK: - PersistentSubscriptions.StreamSelection + Additions


extension PersistentSubscriptionsClient.Create {
    public struct FilterOption{
        let filter: StreamClient.Read.SubscriptionFilter
        let checkpointIntervalMultiplier: UInt32
        
        
        public init(filter: StreamClient.Read.SubscriptionFilter, checkpointIntervalMultiplier: UInt32) {
            self.filter = filter
            self.checkpointIntervalMultiplier = checkpointIntervalMultiplier
        }
        
        func build() -> Request.UnderlyingMessage.AllOptions.FilterOptions{
            return .with{
                switch filter.window{
                case .count:
                    $0.count = .init()
                case let .max(max):
                    $0.max = max
                }
                
                switch filter.type{
                case let .streamName(regex):
                    $0.streamIdentifier = .with{
                        $0.regex = regex
                        $0.prefix = filter.prefixes
                    }
                case let .eventType(regex):
                    $0.eventType = .with{
                        $0.regex = regex
                        $0.prefix = filter.prefixes
                    }
                }
                
                $0.checkpointIntervalMultiplier = checkpointIntervalMultiplier
            }
        }
        
    }
    
    public enum StreamSelection {
        case all(position: StreamClient.Cursor<StreamClient.Read.Position>, filterOption: FilterOption? = nil)
        case specified(streamIdentifier: StreamClient.Identifier, revision: StreamClient.Cursor<UInt64>)
        
        func build(options: inout PersistentSubscriptionsClient.Create.Request.UnderlyingMessage.Options) throws{
            
            switch self {
            case .all(let cursor, let filterOption):
                switch cursor {
                case .start:
                    options.all.start = .init()
                case .end:
                    options.all.end = .init()
                case .at(let pointer):
                    options.all.position = .with{
                        $0.commitPosition = pointer.commit
                        $0.preparePosition = pointer.prepare
                    }
                }
                
                if let filterOption{
                    options.all.filter = filterOption.build()
                }else{
                    options.all.noFilter = .init()
                }
                
                
            case .specified(let identifier, let revisionCursor):
                
                options.streamIdentifier = try identifier.build()
                switch revisionCursor {
                case .start:
                    options.stream.start = .init()
                case .end:
                    options.stream.end = .init()
                case .at(let pointer):
                    options.stream.revision = pointer
                }
                
            }
        }
    }
}
