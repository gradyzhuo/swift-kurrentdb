//
//  ScavengeResponse.swift
//  KurrentOperations
//
//  Created by Grady Zhuo on 2023/12/12.
//

import Foundation
import GRPCEncapsulates

extension Operations {
    /// Response returned when starting or stopping a scavenge operation.
    public struct ScavengeResponse: GRPCResponse {
        /// Lifecycle status of a scavenge operation.
        public enum ScavengeResult: Sendable {
            /// Scavenge has been started.
            case started
            /// Scavenge is currently running.
            case inProgress
            /// Scavenge has been stopped.
            case stopped
            /// Unrecognised status value returned by the server.
            case unrecognized(Int)
        }

        package typealias UnderlyingMessage = EventStore_Client_Operations_ScavengeResp

        let scavengeId: String
        let scavengeResult: ScavengeResult

        package init(from message: UnderlyingMessage) throws {
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
