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
    /// Bearer token authentication (e.g. OAuth/OIDC access token).
    case bearer(token: String)
    /// Mutual TLS authentication using a client certificate and private key.
    case x509(certFile: String, keyFile: String)

    /// Builds the `Authorization` header value for this authentication method.
    ///
    /// - Throws: `KurrentError` when the credentials cannot be encoded, or when the method
    ///   (e.g. `.x509`) is not carried in an `Authorization` header.
    package func makeAuthHeader() throws(KurrentError) -> String {
        switch self {
        case let .credentials(username, password):
            let credentialString = "\(username):\(password)"
            guard let data = credentialString.data(using: .ascii) else {
                throw .encodingError(message: "credentials for user '\(username)' encoding failed.", encoding: .ascii)
            }
            return "Basic \(data.base64EncodedString())"
        case let .bearer(token):
            return "Bearer \(token)"
        case .x509:
            throw .internalParsingError(reason: "X.509 authentication does not use an Authorization header.")
        }
    }
}

extension Authentication: CustomStringConvertible {
    /// Human-readable description of the authentication method.
    public var description: String {
        switch self {
        case .credentials(let username, _):
            "credentials(username: \(username))"
        case .bearer:
            "bearer(token: ***)"
        case .x509(let certFile, _):
            "x509(certFile: \(certFile))"
        }
    }
}
