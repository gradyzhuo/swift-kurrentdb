//
//  Authentication.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/3/24.
//

public enum Authentication: Sendable {
    case credentials(username: String, password: String)

    package func makeBasicAuthHeader() throws(KurrentError) -> String {
        switch self {
        case let .credentials(username, password):
            let credentialString = "\(username):\(password)"
            guard let data = credentialString.data(using: .ascii) else {
                throw .encodingError(message: "\(credentialString) encoding failed.", encoding: .ascii)
            }
            return "Basic \(data.base64EncodedString())"
        }
    }
}
