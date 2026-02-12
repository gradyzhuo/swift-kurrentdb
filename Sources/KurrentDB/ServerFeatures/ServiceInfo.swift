//
//  ServiceInfo.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2025/4/20.
//

import GRPCCore

// repeated SupportedMethod methods = 1;
// string event_store_server_version = 2;
extension ServerFeatures {
    public struct ServiceInfo: Sendable {
        public let serverVersion: String
        public let supportedMethods: [SupportedMethod]
        
        internal func isSupported(method: GRPCCore.MethodDescriptor)->Bool{
            return supportedMethods.contains {
                return $0.serviceName.lowercased() == method.service.fullyQualifiedService.lowercased()
                    && $0.methodName.lowercased() == method.method.lowercased()
            }
        }
    }
}
