//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/5/25.
//

import Foundation
import RegexBuilder

class EndpointParser: ConnctionStringParser{
    typealias RegexType = Regex<(Substring, HostReference.RegexOutput, PortReference.RegexOutput?)>
    typealias Result = [ClientSettings.Endpoint]
    typealias HostReference = Reference<String>
    typealias PortReference = Reference<UInt32>
    
    lazy var regex: RegexType = {
        Regex {
            ChoiceOf {
                "://"
                "@"
                ","
            }
            Capture(as: _host) {
                OneOrMore(
                    .any
                        .subtracting(
                            .anyOf(":?=&")
                        )
                )
            }
            transform: {
                String($0)
            }

            Optionally {
                ":"
                TryCapture(OneOrMore(.digit), as: _port) {
                    UInt32($0, radix: 10)
                }
            }
        }
    }()
    
    let _host: HostReference = .init()
    let _port: PortReference = .init()
    
    func parse(_ connectionString: String) throws -> Result? {
        var connectionString = connectionString
        if let atIndex = connectionString.firstIndex(of: "@") {
            let range = connectionString.startIndex ..< atIndex
            connectionString.replaceSubrange(range, with: "")
        }
        
        let matches = connectionString.matches(of: regex)
        
        return matches.map {
            .init(host: $0[_host], port: $0[_port])
        }
    }
    
    
}
