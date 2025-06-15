//
//  URLScheme.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation

enum URLScheme: String {
    case kurrentdb
    case dnsDiscover

    init?(rawValue: String) {
        switch rawValue {
        case "esdb", "kurrentdb", "kurrent", "kdb":
            self = .kurrentdb
        case "esdb+discover", "kurrentdb+discover", "kurrent+discover", "kdb+discover":
            self = .dnsDiscover
        default:
            return nil
        }
    }
}
