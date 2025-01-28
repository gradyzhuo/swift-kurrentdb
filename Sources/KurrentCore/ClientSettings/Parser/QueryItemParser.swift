//
//  QueryItemParser.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import RegexBuilder

class QueryItemParser: ConnctionStringParser {
    typealias KeyReference = Reference<String>
    typealias ValueReference = Reference<String>
    typealias RegexType = Regex<(Substring, KeyReference.RegexOutput, ValueReference.RegexOutput)>
    typealias Result = [URLQueryItem]

    let _key: KeyReference = .init()
    let _value: ValueReference = .init()
    lazy var regex: RegexType = Regex {
        ChoiceOf {
            "?"
            "&"
        }
        Capture(as: _key) {
            OneOrMore {
                .any.subtracting(.anyOf("?&="))
            }
        } transform: {
            String($0)
        }

        "="
        Capture(as: _value) {
            OneOrMore {
                .any.subtracting(.anyOf("?&="))
            }
        } transform: {
            String($0)
        }
    }

    func parse(_ connectionString: String) throws -> [URLQueryItem]? {
        let queryItemsMatches = connectionString.matches(of: regex)
        return queryItemsMatches.map {
            .init(name: $0[_key], value: $0[_value])
        }
    }
}
