//
//  GRPCClient+Additions.swift
//
//
//  Created by Grady Zhuo on 2023/12/19.
//

import Foundation
import GRPC

extension GRPCClient {
    mutating func configure(by settings: ClientSettings) throws {
        if let user = settings.defaultUserCredentials {
            try defaultCallOptions.customMetadata.replaceOrAdd(name: "Authorization", value: user.basicAuthHeader)
        }
    }
}
