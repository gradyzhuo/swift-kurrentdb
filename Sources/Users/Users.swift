//
//  UserClient.swift
//
//
//  Created by Grady Zhuo on 2023/11/28.
//

import Foundation
import KurrentCore
import GRPCCore
import GRPCEncapsulates
import Logging
import GRPCNIOTransportHTTP2Posix

public typealias UnderlyingService = EventStore_Client_Users_Users

public struct Service: GRPCConcreteClient {
    public typealias Transport = HTTP2ClientTransport.Posix
    public typealias UnderlyingClient = UnderlyingService.Client<Transport>

    
    public private(set) var settings: ClientSettings
    public var callOptions: CallOptions
    
    public init(settings: ClientSettings, callOptions: CallOptions = .defaults){
        self.settings = settings
        self.callOptions = callOptions
    }
    
}

extension Service {
    // MARK: - Create Actions
    public func create(loginName: String, password: String, fullName: String, groups: String...) async throws -> UserDetails? {
        let usecase = Create(loginName: loginName, password: password, fullName: fullName, groups: groups)
        
        _ = try await usecase.perform(settings: settings, callOptions: callOptions)

        let responses = try await details(loginName: loginName)
        return try await responses.first{ _ in true }
    }

    // MARK: - Details Actions

    public func details(loginName: String) async throws -> AsyncThrowingStream<UserDetails, Error> {
        let usecase = Details(loginName: loginName)
        return try await usecase.perform(settings: settings, callOptions: callOptions)
    }
}

extension UserDetails{
    public init(from message: Users.UnderlyingService.Method.Details.Output.UserDetails) throws {
        self.init(
            loginName: message.loginName,
            fullName: message.fullName,
            groups: message.groups,
            lastUpdated: .init(timeIntervalSince1970: .init(message.lastUpdated.ticksSinceEpoch)),
            disabled: message.disabled
        )
    }
}
