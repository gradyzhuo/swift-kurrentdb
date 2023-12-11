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
    public struct StartScavenge: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Operations_StartScavengeReq>
        public typealias Response = Operations.ScavengeResponse

        let threadCount: Int32
        let startFromChunk: Int32
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = .with{
                    $0.threadCount = threadCount
                    $0.startFromChunk = startFromChunk
                }
            }
        }
    }
}
