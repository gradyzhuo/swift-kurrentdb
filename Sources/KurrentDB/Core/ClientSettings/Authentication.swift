//
//  Authentication.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/3/24.
//

/// Authentication method used when connecting to a KurrentDB node.
public enum Authentication: Sendable {
    /// Username and password credentials (HTTP Basic auth).
    case credentials(username: String, password: String)
    /// Mutual TLS authentication using a client certificate and private key.
    case x509(certFile: String, keyFile: String)

    package func makeBasicAuthHeader() throws(KurrentError) -> String {
        switch self {
        case let .credentials(username, password):
            let credentialString = "\(username):\(password)"
            guard let data = credentialString.data(using: .ascii) else {
                throw .encodingError(message: "credentials for user '\(username)' encoding failed.", encoding: .ascii)
            }
            return "Basic \(data.base64EncodedString())"
        case .x509:
            throw .internalParsingError(reason: "X.509 authentication does not use a Basic auth header.")
        }
    }
}

extension Authentication: CustomStringConvertible {
    /// Human-readable description of the authentication method.
    public var description: String {
        switch self {
        case .credentials(let username, _):
            "credentials(username: \(username))"
        case .x509(let certFile, _):
            "x509(certFile: \(certFile))"
        }
    }
}
