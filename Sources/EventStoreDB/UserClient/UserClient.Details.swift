//
//  UserClient.Details.swift
//
//
//  Created by Grady Zhuo on 2023/12/20.
//

import Foundation
import GRPCEncapsulates

extension UserClient {
    public struct Details: UnaryStream {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Users_DetailsReq>

        let loginName: String

        package func build() throws -> Request.UnderlyingMessage {
            .with {
                $0.options.loginName = loginName
            }
        }
    }
}

extension UserClient.Details {
    public struct Response: GRPCResponse {
        public typealias UnderlyingMessage = EventStore_Client_Users_DetailsResp

        let userDetails: User

        public init(from message: UnderlyingMessage) throws {
            userDetails = try .init(from: message.userDetails)
        }
    }
}
