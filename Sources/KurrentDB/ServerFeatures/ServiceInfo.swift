//
//  ServiceInfo.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

//repeated SupportedMethod methods = 1;
//string event_store_server_version = 2;
extension ServerFeatures {
    public struct ServiceInfo: Sendable {
        public let serverVersion: String
        public let supportedMethods: [SupportedMethod]
    }
}

