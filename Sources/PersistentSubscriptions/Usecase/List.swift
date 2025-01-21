//
//  PersistentSubscriptionsClient.List.swift
//
//
//  Created by Grady Zhuo on 2023/12/11.
//

import KurrentCore
import GRPCCore
import GRPCEncapsulates

public struct List: UnaryUnary {
    public typealias Client = PersistentSubscriptions.Service
    public typealias UnderlyingRequest = UnderlyingService.Method.List.Input
    public typealias UnderlyingResponse = UnderlyingService.Method.List.Output
    public typealias Response = [PersistentSubscription.SubscriptionInfo]
    
    public let options: Options
    
    public init(options: Options) {
        self.options = options
    }
    
    package func requestMessage() throws -> UnderlyingRequest {
        return .with {
            $0.options = options.build()
        }
    }
    
    public func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
        return try await client.list(request: request, options: callOptions){
            try $0.message.subscriptions.map { .init(from: $0) }
        }
    }
    

}

extension List {
    public struct Options: EventStoreOptions {
        public typealias UnderlyingMessage = UnderlyingRequest.Options

        private var options: UnderlyingMessage
        
        private init(options: UnderlyingMessage) {
            self.options = options
        }

        public static func listAllScriptions() -> Self {
            var options = UnderlyingMessage()
            options.listAllSubscriptions = .init()
            return .init(options: options)
        }

        @discardableResult
        public static func listForStream(_ streamIdentifier: Stream.Identifier) throws -> Self {
            var options = UnderlyingMessage()
            options.listForStream.stream = try streamIdentifier.build()
            return .init(options: options)
        }

        package func build() -> UnderlyingMessage {
            options
        }
    }
}
