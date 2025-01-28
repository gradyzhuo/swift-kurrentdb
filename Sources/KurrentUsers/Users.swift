//
//  Users.swift
//  KurrentUsers
//
//  Created by Grady Zhuo on 2023/11/28.
//
@_exported
import KurrentCore

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct Users: GRPCConcreteService {
    package typealias Client = EventStore_Client_Users_Users.Client<HTTP2ClientTransport.Posix>

    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    public init(settings: ClientSettings, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.settings = settings
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension Users {}

extension Users {
    // MARK: - Create Actions

    public func create(loginName: String, password: String, fullName: String, groups: String...) async throws -> UserDetails? {
        let usecase = Create(loginName: loginName, password: password, fullName: fullName, groups: groups)

        _ = try await usecase.perform(settings: settings, callOptions: callOptions)

        let responses = try await details(loginName: loginName)
        return try await responses.first { _ in true }
    }

    // MARK: - Details Actions

    public func details(loginName: String) async throws -> AsyncThrowingStream<UserDetails, Error> {
        let usecase = Details(loginName: loginName)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}
