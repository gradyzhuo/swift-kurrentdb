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

        if let authentication = settings.authentication {
            do {
                try replaceOrAddString(authentication.makeBasicAuthHeader(), forKey: "Authorization")
            } catch {
                logger.error("Could not setting Authorization with credentials: \(authentication).\n Original error:\(error).")
            }
        }
    }
}
