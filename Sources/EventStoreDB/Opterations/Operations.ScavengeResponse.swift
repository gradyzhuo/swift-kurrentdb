//
//  Operations.ScavengeResponse.swift
//
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCSupport

extension OperationsClient {
    public struct ScavengeResponse: GRPCResponse {
        public enum ScavengeResult {
            case started
            case inProgress
            case stopped
            case unrecognized(Int)
        }

        public typealias UnderlyingMessage = EventStore_Client_Operations_ScavengeResp

        let scavengeId: String
        let scavengeResult: ScavengeResult

        public init(from message: UnderlyingMessage) throws {
            scavengeId = message.scavengeID
            scavengeResult = switch message.scavengeResult {
            case .started:
                .started
            case .inProgress:
                .inProgress
            case .stopped:
                .stopped
            case let .UNRECOGNIZED(value):
                .unrecognized(value)
            }
        }
    }
}
