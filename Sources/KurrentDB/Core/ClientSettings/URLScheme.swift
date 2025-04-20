//
//  ClientSettings.ValidScheme.swift
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
        case "esdb", "kurrentdb":
            self = .kurrentdb
        case "esdb+discover", "kurrentdb+discover":
            self = .dnsDiscover
        default:
            return nil
        }
    }
}

