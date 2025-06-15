//
//  TopologyClusterMode.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/2/7.
//

import Foundation
import NIOCore

public enum TopologyClusterMode: Sendable {
    case standalone(endpoint: Endpoint)
    case dns(domain: Endpoint)
    case seeds([Endpoint])
}
