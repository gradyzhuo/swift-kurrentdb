//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/20.
//

import Foundation
import GRPCSupport

@available(macOS 13.0, *)
extension UserClient{
    public struct Create: UnaryUnary {
        public typealias Request = GenericGRPCRequest<EventStore_Client_Users_CreateReq>
        
        public typealias Response = DiscardedResponse<EventStore_Client_Users_CreateResp>
        
        let loginName: String
        let password: String
        let fullName: String
        
        let groups: [String]
        
        public func build() throws -> GRPCSupport.EventStore_Client_Users_CreateReq {
            return .with{
                $0.options.loginName = loginName
                $0.options.password = password
                $0.options.fullName = fullName
                $0.options.groups = groups
            }
        }
        
        public init(loginName: String, password: String, fullName: String, groups: [String] = []) {
            self.loginName = loginName
            self.password = password
            self.fullName = fullName
            self.groups = groups
        }
        
    }
    
}
