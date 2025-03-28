//
//  PersistentSubscriptionsClient.Read.swift
//  KurrentPersistentSubscriptions
//
//  Created by Grady Zhuo on 2023/12/8.
//
import Foundation
import GRPCCore
import GRPCEncapsulates

extension PersistentSubscriptions where Target == PersistentSubscription.AllGroup{
    public struct ReadAllGroup: StreamStream {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = UnderlyingService.Method.Read.Input
        package typealias UnderlyingResponse = UnderlyingService.Method.Read.Output
        package typealias Response = ReadResponse
        package typealias Responses = Subscription
        
        public let group: String
        public let options: ReadOptions

        package init(group: String, options: ReadOptions) {
            self.group = group
            self.options = options
        }

        package func requestMessages() throws -> [UnderlyingRequest] {
            [
                .with {
                    $0.options = options.build()
                    $0.options.all = .init()
                    $0.options.groupName = group
                },
            ]
        }

        package func send(client: UnderlyingClient, metadata: Metadata, callOptions: CallOptions) async throws -> Responses {
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




