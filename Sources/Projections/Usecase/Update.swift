//
//  ProjectionsClient.Update.swift
//
//
//  Created by Grady Zhuo on 2023/11/26.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

public struct Update: UnaryUnary {
    public typealias Client = Projections.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.Update.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.Update.Output
    public typealias Response = DiscardedResponse<UnderlyingResponse>

    public let name: String
    public let query: String?
    public let options: Options
    
    public init(name: String, query: String? = nil, options: Options) {
        self.name = name
        self.query = query
        self.options = options
    }

    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
            $0.options.name = name
            if let query {
                $0.options.query = query
            }
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.update(request: request, options: callOptions){
            try handle(response: $0)
        }
    }
    
    

}
extension Update {
    public struct Options: EventStoreOptions {
        public enum EmitOption: Sendable {
            case noEmit
            case enable(Bool)
        }

        public typealias UnderlyingMessage = UnderlyingRequest.Options

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
