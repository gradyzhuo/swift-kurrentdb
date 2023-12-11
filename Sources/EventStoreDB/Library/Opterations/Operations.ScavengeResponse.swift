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
    public struct ScavengeResponse: GRPCResponse {
        
        public enum ScavengeResult{
            case started
            case inProgress
            case stopped
            case unrecognized(Int)
        }
        public typealias UnderlyingMessage = EventStore_Client_Operations_ScavengeResp
        
        let scavengeId: String
        let scavengeResult: ScavengeResult
        
        public init(from message: UnderlyingMessage) throws {
            self.scavengeId = message.scavengeID
            self.scavengeResult = switch message.scavengeResult {
            case .started:
                    .started
            case .inProgress:
                    .inProgress
            case .stopped:
                    .stopped
            case .UNRECOGNIZED(let value):
                    .unrecognized(value)
            }
            
        }
    }
}
