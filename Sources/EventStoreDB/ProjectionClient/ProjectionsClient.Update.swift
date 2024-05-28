//
//  ProjectionsClient.Update.swift
//
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCEncapsulates

extension ProjectionsClient {
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

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options = options.build()
                $0.options.name = name
                if let query {
                    $0.options.query = query
                }
            }
        }
    }
}

extension ProjectionsClient.Update {
    public struct Options: EventStoreOptions {
        public enum EmitOption: Sendable {
            case noEmit
            case enable(Bool)
        }

        public typealias UnderlyingMessage = EventStore_Client_Projections_UpdateReq.Options

        public var emitOption: EmitOption = .noEmit

        public func build() -> UnderlyingMessage {
            .with {
                switch emitOption {
                case .noEmit:
                    $0.noEmitOptions = .init()
                case let .enable(enabled):
                    $0.emitEnabled = enabled
                }
            }
        }

        @discardableResult
        public func noEmit() -> Self {
            withCopy { options in
                options.emitOption = .noEmit
            }
        }

        @discardableResult
        public func emit(enabled: Bool) -> Self {
            withCopy { options in
                options.emitOption = .enable(enabled)
            }
        }
    }
}
