//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/11/26.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension Projections {
    public struct Update: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_UpdateReq>
        public typealias Response = DiscardedResponse<EventStore_Client_Projections_UpdateResp>
        
        public let name: String
        public let query: String?
        public let options: Options
        
        init(name: String, query: String? = nil, options: Options) {
            self.name = name
            self.query = query
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.name = name
                if let query = query {
                    $0.options.query = query
                }
            }
        }
    }
}

@available(macOS 13.0, *)
extension Projections.Update {
    public final class Options: EventStoreOptions {
        
        public enum EmitOption {
            case noEmit
            case enable(Bool)
        }
        
        public typealias UnderlyingMessage = EventStore_Client_Projections_UpdateReq.Options
        
        public var options: UnderlyingMessage
        
        public init() {
            self.options = .init()
            self.emit(option: .noEmit)
        }
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
        @discardableResult
        public func emit(option: EmitOption)->Self{
            switch option {
            case .noEmit:
                self.options.noEmitOptions = .init()
            case .enable(let enabled):
                self.options.emitEnabled = enabled
            }
            return self
        }
        
    }
}
