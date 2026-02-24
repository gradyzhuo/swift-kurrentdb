//
//  SupportedMethod.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/20.
//

extension ServerFeatures {
    public struct SupportedMethod: Sendable {
        public let methodName: String
        public let serviceName: String
        public let features: [String]
    }
}
