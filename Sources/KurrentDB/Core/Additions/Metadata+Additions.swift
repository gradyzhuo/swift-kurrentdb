//
//  Metadata+Additions.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//
import GRPCCore

extension Metadata {
    /// Builds request metadata from client settings, optionally overriding the authentication
    /// for a single call.
    ///
    /// - Parameters:
    ///   - settings: Client settings providing the default authentication.
    ///   - overriding: When non-nil, this authentication replaces the client-level one for this
    ///     request (per-call credentials). When nil, the client-level authentication is used.
    ///
    /// - Throws: ``KurrentError/internalClientError(reason:)`` when a per-call ``Authentication/x509(certFile:keyFile:)``
    ///   is supplied. Mutual TLS identity is established when the TLS connection is built, so it
    ///   cannot be swapped per request via metadata — failing loudly beats silently authenticating
    ///   as the client-level identity.
    package init(from settings: ClientSettings, overriding overrideAuthentication: Authentication? = nil) throws(KurrentError) {
        self.init()

        if case .x509 = overrideAuthentication {
            throw .internalClientError(reason: "Per-call X.509 authentication is not supported: a client certificate is bound to the TLS connection, not to individual requests. Configure `.x509(certFile:keyFile:)` on `ClientSettings` instead.")
        }

        guard let authentication = overrideAuthentication ?? settings.authentication else {
            return
        }

        // Client-level X.509 legitimately carries no `Authorization` header — the identity travels
        // with the TLS handshake — so an absent header here is expected, not a failure.
        if case .x509 = authentication {
            return
        }

        do {
            try replaceOrAddString(authentication.makeAuthHeader(), forKey: "Authorization")
        } catch {
            logger.error("Could not setting Authorization with credentials: \(authentication).\n Original error:\(error).")
        }
    }
}
