//
//  UserCredentials.swift
//
//
//  Created by Grady Zhuo on 2024/1/1.
//

import Foundation

public struct UserCredentials {
    public let username: String
    public let password: String

    public init(username: String, password: String) {
        self.username = username
        self.password = password
    }
}

extension UserCredentials {
    var basicAuthHeader: String {
        get throws {
            let credentialString = "\(username):\(password)"
            guard let data = credentialString.data(using: .ascii) else {
                throw ClientSettingsError.encodingError(message: "\(credentialString) encoding failed.", encoding: .ascii)
            }
            return "Basic \(data.base64EncodedString())"
        }
    }
}
