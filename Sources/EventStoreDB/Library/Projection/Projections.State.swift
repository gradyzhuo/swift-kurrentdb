//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/11/27.
//

import Foundation
import SwiftProtobuf
import GRPCSupport

@available(macOS 13.0, *)
extension Projections {
    public struct State : UnaryUnary{
        public typealias Request = GenericGRPCRequest<EventStore_Client_Projections_StateReq>
        
        public let name: String
        public let options: Options
        
        init(name: String, options: Options) {
            self.name = name
            self.options = options
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.name = name
            }
        }
        
    }
}


@available(macOS 13.0, *)
extension Projections.State {
    
    public struct Response: GRPCJSONDecodableResponse {
        public typealias UnderlyingMessage = EventStore_Client_Projections_StateResp
        
        public private(set) var jsonValue: SwiftProtobuf.Google_Protobuf_Value
        
        public init(from message: UnderlyingMessage) throws {
            self.jsonValue = message.state
        }
        
    }
    
    public final class Options: EventStoreOptions {
        
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        var options: UnderlyingMessage
        
        public init() {
            self.options = .init()
        }
        
        public func partition(_ partition: String) -> Self{
            self.options.partition = partition
            return self
        }
        
        
        public func build() -> UnderlyingMessage {
            return options
        }
        
    }
}


