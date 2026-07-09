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
    package init(from settings: ClientSettings, overriding overrideAuthentication: Authentication? = nil) {
        self.init()

        if let authentication = overrideAuthentication ?? settings.authentication {
            do {
                try replaceOrAddString(authentication.makeAuthHeader(), forKey: "Authorization")
            } catch {
                logger.error("Could not setting Authorization with credentials: \(authentication).\n Original error:\(error).")
            }
        }
    }
}
