//
//  ConnctionStringParser.swift
//
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import RegexBuilder

protocol ConnctionStringParser {
    associatedtype Result

    mutating func parse(_ connectionString: String) throws -> Result?
}
