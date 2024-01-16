//
//  String+Additions.swift
//
//
//  Created by Grady Zhuo on 2024/1/1.
//

import Foundation

extension String {
    public func parse() throws -> ClientSettings {
        try ClientSettings.parse(connectionString: self)
    }
}
