//
//  ServerFeatures.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2Posix
import Logging
import NIO

public struct ServerFeatures: GRPCConcreteService {
    package typealias UnderlyingClient = EventStore_Client_ServerFeatures_ServerFeatures.Client<HTTP2ClientTransport.Posix>

    public private(set) var node: Node
    public var callOptions: CallOptions
    public let eventLoopGroup: EventLoopGroup

    internal init(node: Node, callOptions: CallOptions = .defaults, eventLoopGroup: EventLoopGroup = .singletonMultiThreadedEventLoopGroup) {
        self.node = node
        self.callOptions = callOptions
        self.eventLoopGroup = eventLoopGroup
    }
}

extension ServerFeatures {
//    public func read() async throws(KurrentError) -> [MemberInfo] {
//        let usecase = Read()
//        return try await usecase.perform(settings: settings, callOptions: callOptions).reduce(into: .init()) { partialResult, memberInfo in
//            partialResult.append(memberInfo)
//        }
//    }
}
