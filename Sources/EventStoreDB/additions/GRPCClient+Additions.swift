//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/12/19.
//

import Foundation
import GRPC

extension GRPCClient {
    
    internal mutating func configure(by settings: ClientSettings) throws {
        if let user = settings.defaultUserCredentials {
            self.defaultCallOptions.customMetadata.replaceOrAdd(name: "Authorization", value: try user.basicAuthHeader)
        }
    }
}
