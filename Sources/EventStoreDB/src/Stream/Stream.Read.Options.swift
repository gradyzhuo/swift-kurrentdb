//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension StreamClient.Read {
    
    public final class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Streams_ReadReq.Options
        
        public var options: UnderlyingMessage
        
        public init() {
            self.options = .init()
            
            self.set(uuidOption: .string)
                .noFilter()
                .countBy(limit: .max)
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        @discardableResult
        public func filterOnStream(regex: String, closure: ((inout StreamClient.Read.SubscriptionFilter)->())? = nil)->Self{
            var filter = StreamClient.Read.SubscriptionFilter.onStreamName(regex: regex)
            closure?(&filter)
            filter.build(options: &options)
            return self
        }
        
        @discardableResult
        public func filterOnEventType(regex: String, closure: (inout StreamClient.Read.SubscriptionFilter)->())->Self{
            var filter = StreamClient.Read.SubscriptionFilter.onEventType(regex: regex)
            closure(&filter)
            filter.build(options: &options)
            return self
        }
        
        @discardableResult
        public func noFilter() -> Self {
            options.noFilter = .init()
            return self
        }
        
        @discardableResult
        public func set(resolveLinks: Bool)->Self {
            options.resolveLinks = resolveLinks
            return self
        }
        
        @discardableResult
        public func countBy(limit: UInt64)->Self {
            options.count = limit
            return self
        }
        
        @discardableResult
        public func countBySubscription()->Self {
            options.subscription = .init()
            return self
        }
        
        @discardableResult
        public func set(uuidOption: StreamClient.Read.UUIDOption)->Self {
            uuidOption.build(options: &options)
            return self
        }
        
        @discardableResult
        public func set(compatibility: UInt32)->Self {
            StreamClient.Read.ControlOption.compatibility(compatibility)
                .build(options: &options)
            return self
        }
    }
    
}


