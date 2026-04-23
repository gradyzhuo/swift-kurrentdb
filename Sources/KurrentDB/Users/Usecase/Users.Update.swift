//
//  Users.Update.swift
//  KurrentUsers
//
//  Created by 卓俊諺 on 2025/1/16.
//

import Foundation
import GRPCCore
import GRPCEncapsulates

extension Users {
    /// Usecase that sends an update-user RPC to KurrentDB.
    public struct Update: UnaryUnary {
        package typealias ServiceClient = UnderlyingClient
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

        package var methodDescriptor: GRPCCore.MethodDescriptor {
            ServiceClient.UnderlyingService.Method.Update.descriptor
        }

        package static var name: String {
            "Users.\(Self.self)"
        }

        let loginName: String
        let password: String
        let options: Options

        public init(loginName: String, password: String, options: Options) {
            self.loginName = loginName
            self.password = password
            self.options = options
        }

        package func requestMessage() throws -> UnderlyingRequest {
            .with {
                $0.options = options.build()
                $0.options.loginName = loginName
                $0.options.password = password
            }
        }

        package func send(connection: GRPCClient<Transport>, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            let client = ServiceClient(wrapping: connection)
            return try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Users.Update {
    /// Builder for profile fields that can be modified during an update operation.
    public struct Options: CommandOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        /// Updated full display name, or `nil` to leave unchanged.
        public fileprivate(set) var fullName: String?
        /// Updated group memberships, or `nil` to leave unchanged.
        public fileprivate(set) var groups: [UserGroup]?

        public init() {}

        /// Returns a copy with `fullName` set to the given value.
        public func set(fullName: String) -> Self {
            withCopy { options in
                options.fullName = fullName
            }
        }

        /// Returns a copy with the given groups appended to the existing group list.
        public func add(groups: UserGroup...) -> Self {
            withCopy { options in
                options.groups?.append(contentsOf: groups)
            }
        }

        /// Returns a copy with the group list replaced by the given groups.
        public func set(groups: UserGroup...) -> Self {
            withCopy { options in
                options.groups = groups
            }
        }

        package func build() -> UnderlyingMessage {
            .with {
                if let fullName {
                    $0.fullName = fullName
                }
                if let groups {
                    $0.groups = groups.map(\.rawValue)
                }
            }
        }
    }
}
