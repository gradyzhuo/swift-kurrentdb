//
//  Metadata+Additions.swift
//  KurrentCore
//
//  Created by 卓俊諺 on 2025/1/20.
//
import GRPCCore

extension Metadata {
    package init(from settings: ClientSettings) {
        self.init()

        if let credentials = settings.defaultUserCredentials {
            do {
                try replaceOrAddString(credentials.makeBasicAuthHeader(), forKey: "Authorization")
            } catch {
                logger.error("Could not setting Authorization with credentials: \(credentials).\n Original error:\(error).")
            }
        }
    }
}
