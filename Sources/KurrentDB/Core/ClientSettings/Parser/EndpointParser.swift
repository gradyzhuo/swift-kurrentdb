//
//  EndpointParser.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/5/25.
//

import Foundation
import RegexBuilder

class EndpointParser: ConnctionStringParser {
    typealias RegexType = Regex<(Substring, HostReference.RegexOutput, PortReference.RegexOutput?)>
    typealias Result = [Endpoint]
    typealias HostReference = Reference<String>
    typealias PortReference = Reference<UInt32>

    let ipv4Regex = Regex {
        Anchor.wordBoundary
        Regex {
            Repeat(count: 3) {
                Regex {
                    ChoiceOf {
                        Regex {
                            One("25")
                            One("0" ... "5")
                        }
                        Regex {
                            One("2")
                            One("0" ... "4")
                            One(.digit)
                        }
                        Regex {
                            One("1")
                            One(.digit)
                            One(.digit)
                        }
                        Regex {
                            Optionally {
                                One("1" ... "9")
                            }
                            One(.digit)
                        }
                    }
                    One(".")
                }
            }
        }

        Regex {
            ChoiceOf {
                Regex {
                    One("25")
                    One("0" ... "5")
                }

                Regex {
                    One("2")
                    One("0" ... "4")
                    One(.digit)
                }

                Regex {
                    One("1")
                    One(.digit)
                    One(.digit)
                }

                Regex {
                    Optionally {
                        One("1" ... "9")
                    }
                    One(.digit)
                }
            }
        }
        Anchor.wordBoundary
    }

    let hostRegex = Regex {
        Anchor.wordBoundary
        OneOrMore {
            ChoiceOf {
                "A" ... "Z"
                "a" ... "z"
            }
            ZeroOrMore {
                One(.word.subtracting(.anyOf(":?=&")))
            }
            Optionally {
                One(.anyOf(".-_"))
            }
        }
        Anchor.wordBoundary
    }

    lazy var regex: RegexType = Regex {
        ChoiceOf {
            "://"
            "@"
            ","
        }
        Capture(as: _host) {
            ChoiceOf {
                ipv4Regex
                hostRegex
            }
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
