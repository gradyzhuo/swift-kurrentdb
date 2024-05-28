//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/25.
//

import Foundation

extension ClientSettings {
    enum ValidScheme: String {
        case esdb
        case dnsDiscover = "esdb+discover"
    }
}
