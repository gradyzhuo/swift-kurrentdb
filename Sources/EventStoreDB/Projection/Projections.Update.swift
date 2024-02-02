//
//  Projections.Update.swift
//
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCSupport

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

        public func build() throws -> Request.UnderlyingMessage {
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
    public final class Options: EventStoreOptions {
        public enum EmitOption {
            case noEmit
            case enable(Bool)
        }

        public typealias UnderlyingMessage = EventStore_Client_Projections_UpdateReq.Options

        public var options: UnderlyingMessage

        public init() {
            options = .init()
            emit(option: .noEmit)
        }

        public func build() -> UnderlyingMessage {
            options
        }

        @discardableResult
        public func emit(option: EmitOption) -> Self {
            switch option {
            case .noEmit:
                options.noEmitOptions = .init()
            case let .enable(enabled):
                options.emitEnabled = enabled
            }
            return self
        }
    }
}
