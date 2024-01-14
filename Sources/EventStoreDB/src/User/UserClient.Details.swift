//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/20.
//

import Foundation
import GRPCSupport


extension UserClient {
    
    public struct Details: UnaryStream {
        
        public typealias Request = GenericGRPCRequest<EventStore_Client_Users_DetailsReq>
        
        let loginName: String
        
        init(loginName: String) {
            self.loginName = loginName
        }
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
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
            self.userDetails = try .init(from: message.userDetails)
        }
    }
    
    
}
