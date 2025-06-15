//
//  ReadAnyTarget.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/28.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2
import KurrentDB

extension PersistentSubscriptions where Target == PersistentSubscription.AnyTarget {
    @available(*, deprecated, message: "This is only compatible with the original function.")
    public struct ReadAnyTarget: StreamStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Read.Output
        package typealias Response = ReadResponse
        package typealias Responses = Subscription

        public let streamSelector: StreamSelector<StreamIdentifier>
        public let group: String
        public let options: ReadOptions

        package init(streamSelector: StreamSelector<StreamIdentifier>, group: String, options: ReadOptions) {
            self.streamSelector = streamSelector
            self.group = group
            self.options = options
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            try [
                .with {
                    switch streamSelector {
                    case let .specified(streamIdentifier):
                        $0.options.streamIdentifier = try streamIdentifier.build()
                    case .all:
                        $0.options.all = .init()
                    }
                    $0.options.groupName = group
                },
            ]
        }

        package func send(connection: GRPCClient<HTTP2ClientTransport.Posix>, metadata: Metadata, callOptions: CallOptions) async throws -> Subscription {
            let client = ServiceClient(wrapping: connection)
            let responses = AsyncThrowingStream.makeStream(of: ReadResponse.self)

            let writer = Subscription.Writer()
            let requestMessages = try requestMessages()
            writer.write(messages: requestMessages)
            Task {
                try await client.read(metadata: metadata, options: callOptions) {
                    try await $0.write(contentsOf: writer.sender)
                } onResponse: {
                    for try await message in $0.messages {
                        let response = try handle(message: message)
                        responses.continuation.yield(response)
                    }
                }
            }
            return try await .init(requests: writer, responses: responses.stream)
        }
    }
}
