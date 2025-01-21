//
//  GRPCCallable.swift
//
//
//  Created by Grady Zhuo on 2023/10/29.
//

import Foundation
import GRPCCore
import SwiftProtobuf

public protocol Usecase {
    associatedtype Transport: ClientTransport
    associatedtype Client: GRPCConcreteClient where Client.Transport == Transport
}

package protocol UnaryUnary: Usecase, UnaryRequestBuildable, UnaryResponseHandlable {
    func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response
}

package protocol UnaryStream: Usecase, UnaryRequestBuildable, StreamResponseHandlable {
    func send(client: Client.UnderlyingClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Responses
}

package protocol StreamUnary: Usecase, StreamRequestBuildable, UnaryResponseHandlable {
    func send(client: Client.UnderlyingClient, request: StreamingClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response
}

package protocol StreamStream: Usecase, StreamRequestBuildable, StreamResponseHandlable {
    func send(client: Client.UnderlyingClient, metadata: Metadata, callOptions: CallOptions) async throws -> Responses
}

