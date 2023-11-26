//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/10/29.
//

import Foundation

@available(macOS 10.15, *)
extension Stream.Read {
    
    public class Options: EventStoreOptions {
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
        public func filterOnStream(regex: String, closure: ((inout Stream.Read.SubscriptionFilter)->())? = nil)->Self{
            var filter = Stream.Read.SubscriptionFilter.onStreamName(regex: regex)
            closure?(&filter)
            filter.build(options: &options)
            return self
        }
        
        @discardableResult
        public func filterOnEventType(regex: String, closure: (inout Stream.Read.SubscriptionFilter)->())->Self{
            var filter = Stream.Read.SubscriptionFilter.onStreamName(regex: regex)
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
        public func set(uuidOption: Stream.Read.UUIDOption)->Self {
            uuidOption.build(options: &options)
            return self
        }
        
        @discardableResult
        public func set(compatibility: UInt32)->Self {
            Stream.Read.ControlOption.compatibility(compatibility)
                .build(options: &options)
            return self
        }
    }
    
}


