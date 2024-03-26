//
//  UserClient.swift
//
//
//  Created by Grady Zhuo on 2023/11/28.
//

import Foundation
import GRPC
import GRPCSupport
import Logging

public struct User: GRPCResponse {
    public typealias UnderlyingMessage = EventStore_Client_Users_DetailsResp.UserDetails

    public var loginName: String
    public var fullName: String

    public var groups: [String]
    public var lastUpdated: Date
    public var disabled: Bool

    public init(loginName: String, fullName: String, groups: [String], lastUpdated: Date, disabled: Bool) {
        self.loginName = loginName
        self.fullName = fullName
        self.groups = groups
        self.lastUpdated = lastUpdated
        self.disabled = disabled
    }

    public init(from message: UnderlyingMessage) throws {
        self.init(
            loginName: message.loginName,
            fullName: message.fullName,
            groups: message.groups,
            lastUpdated: .init(timeIntervalSince1970: .init(message.lastUpdated.ticksSinceEpoch)),
            disabled: message.disabled
        )
    }
}

public struct UserClient: ConcreteClient {
    public typealias UnderlyingClient = EventStore_Client_Users_UsersAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions

    public init(channel: GRPCChannel, callOptions: CallOptions) {
        self.channel = channel
        self.callOptions = callOptions
    }

}

extension UserClient {
    // MARK: - Create Actions

    public func create(loginName: String, password: String, fullName: String, groups: String...) async throws -> User? {
        let handler = Create(loginName: loginName, password: password, fullName: fullName, groups: groups)
        let request = try handler.build()

        _ = try await underlyingClient.create(request)

        let responses = try details(loginName: loginName)
        var iterator = responses.makeAsyncIterator()
        return await iterator.next()
    }

    // MARK: - Details Actions

    public func details(loginName: String) throws -> AsyncStream<User> {
        let handler = Details(loginName: loginName)
        let request = try handler.build()

        let responses = try handler.handle(responses: underlyingClient.details(request))

        return .init { continuation in
            Task {
                for await response in responses {
                    continuation.yield(response.userDetails)
                }
                continuation.finish()
            }
        }
    }
}
