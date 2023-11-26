//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/26.
//

import Foundation

@available(macOS 13.0, *)
extension Projection.ContinuousCreate {
    public class Options: EventStoreOptions {
        public typealias UnderlyingMessage = EventStore_Client_Projections_CreateReq.Options
        
        var options: UnderlyingMessage
        
        public var emitEnabled: Bool {
            didSet{
                options.continuous.emitEnabled = emitEnabled
            }
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        public var trackEmittedStreams: Bool{
            didSet{
                options.continuous.trackEmittedStreams = trackEmittedStreams
            }
        }
        
        public init() {
            self.options = .with{
                $0.continuous = .init()
            }
            self.emitEnabled = true
            self.trackEmittedStreams = true
        }
        
        @discardableResult
        public func emit(enabled: Bool)->Self{
            self.emitEnabled = enabled
            return self
        }
        
        @discardableResult
        public func trackEmittedStreams(_ trackEmittedStreams: Bool)->Self{
            self.trackEmittedStreams = trackEmittedStreams
            return self
        }
        
    }
}
