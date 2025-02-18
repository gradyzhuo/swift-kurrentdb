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
    public struct Update: UnaryUnary {
        package typealias ServiceClient = Client
        package typealias UnderlyingRequest = ServiceClient.UnderlyingService.Method.Update.Input
        package typealias UnderlyingResponse = ServiceClient.UnderlyingService.Method.Update.Output
        package typealias Response = DiscardedResponse<UnderlyingResponse>

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

        package func send(client: ServiceClient, request: ClientRequest<UnderlyingRequest>, callOptions: CallOptions) async throws -> Response {
            try await client.update(request: request, options: callOptions) {
                try handle(response: $0)
            }
        }
    }
}

extension Users.Update {
    public struct Options: EventStoreOptions {
        package typealias UnderlyingMessage = UnderlyingRequest.Options

        public fileprivate(set) var fullName: String?
        public fileprivate(set) var groups: [String]?

        public init() {
            
        }

        public func set(fullName: String) -> Self {
            withCopy { options in
                options.fullName = fullName
            }
        }
        
        public func add(groups: String...) -> Self {
            withCopy { options in
                options.groups?.append(contentsOf: groups)
            }
        }
        
        public func set(groups: String...) -> Self {
            withCopy { options in
                options.groups = groups
            }
        }

        package func build() -> UnderlyingMessage {
            return .with {
                if let fullName {
                    $0.fullName = fullName
                }
                if let groups {
                    $0.groups = groups
                }
            }
        }
    }
}
