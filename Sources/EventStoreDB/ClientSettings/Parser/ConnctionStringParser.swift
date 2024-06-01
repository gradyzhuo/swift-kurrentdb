//
//  ConnctionStringParser.swift
//
//
//  Created by 卓俊諺 on 2024/5/25.
//

import Foundation
import RegexBuilder

protocol ConnctionStringParser {
    associatedtype RegexType: RegexComponent
    associatedtype Result

    var regex: RegexType { set get }

    mutating func parse(_ connectionString: String) throws -> Result?
}
