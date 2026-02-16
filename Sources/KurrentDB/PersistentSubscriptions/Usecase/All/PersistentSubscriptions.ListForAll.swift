//
//  PersistentSubscriptions.ListForAll.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/11.
//

import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.All {
    public struct ListForAll: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.List.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.List.Output
        package typealias Response = [PersistentSubscription.SubscriptionInfo]

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.List.descriptor
        }

        package static var name: String {
            "PersistentSubscriptions.\(Self.self)"
        }

        public let filter: ListFilter

        package init(filter: ListFilter) {
            self.filter = filter
        }

        package func requestMessage() throws -> UnderlyingRequest {
            try .with {
                switch filter {
                case .allSubscriptions:
                    $0.options.listAllSubscriptions = .init()
                case let .stream(streamIdentifier):
                    if streamIdentifier == .all {
                        $0.options.listForStream.all = .init()
                    } else {
                        $0.options.listForStream.stream = try streamIdentifier.build()
                    }
                }
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.list(request: request, options: callOptions) {
                try $0.message.subscriptions.map { .init(from: $0) }
            }
        }
    }
}

extension PersistentSubscriptions.ListForAll {
    public enum ListFilter: Sendable {
        case allSubscriptions
        case stream(StreamIdentifier)

        static func stream(_ name: String) -> Self {
            .stream(.init(name: name))
        }
    }
}
