//
//  ConnctionStringParser.swift
//
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import RegexBuilder

protocol ConnctionStringParser {
    associatedtype RegexType: RegexComponent
    associatedtype Result

    var regex: RegexType { set get }

    mutating func parse(_ connectionString: String) throws -> Result?
}
