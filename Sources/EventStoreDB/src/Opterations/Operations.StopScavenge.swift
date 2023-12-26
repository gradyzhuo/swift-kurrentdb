//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/12.
//

import Foundation
import GRPCSupport


@available(macOS 13.0, *)
extension OperationsClient {
    
    public struct StopScavenge: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Operations_StopScavengeReq>
        public typealias Response = OperationsClient.ScavengeResponse
        
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
