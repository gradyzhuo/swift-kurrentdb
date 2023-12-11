//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport


@available(macOS 10.15, *)
extension Operations {
    
    public struct StopScavenge: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Operations_StopScavengeReq>
        public typealias Response = Operations.ScavengeResponse
        
        let scavengeId: String
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = .with{
                    $0.scavengeID = scavengeId
                }
            }
        }
        
    }
    
    
}
