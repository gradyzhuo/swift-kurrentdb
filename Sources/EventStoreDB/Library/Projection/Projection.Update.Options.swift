//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/26.
//

import Foundation

@available(macOS 13.0, *)
extension Projection.Update {
    public class Options: EventStoreOptions {
        
        public enum EmitOption {
            case no
            case enable(Bool)
        }
        
        public typealias UnderlyingMessage = EventStore_Client_Projections_UpdateReq.Options
        
        public var options: UnderlyingMessage
        
        public init() {
            self.options = .init()
            self.noEmit()
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        @discardableResult
        public func emit(enabled: Bool)->Self{
            self.options.emitEnabled = enabled
            return self
        }
        
        @discardableResult
        public func noEmit()->Self{
            self.options.noEmitOptions = .init()
            return self
        }
//
//        @discardableResult
//        public func trackEmittedStreams(_ trackEmittedStreams: Bool)->Self{
//            self.trackEmittedStreams = trackEmittedStreams
//            return self
//        }
        
    }
}
