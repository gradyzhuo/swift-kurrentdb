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
            // RFC 1123: hostname labels may start with a letter or digit
            ChoiceOf {
                "A" ... "Z"
                "a" ... "z"
                "0" ... "9"
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

    func parse(_ connectionString: String) -> Result? {
        var connectionString = connectionString
        // Only look for '@' in the authority section (before '?' query string)
        // to avoid incorrectly stripping when query param values contain '@'
        let queryStart = connectionString.firstIndex(of: "?") ?? connectionString.endIndex
        let authority = connectionString[..<queryStart]
        if let atIndex = authority.firstIndex(of: "@") {
            let range = connectionString.startIndex ..< atIndex
            connectionString.replaceSubrange(range, with: "")
        }

        let matches = connectionString.matches(of: regex)

        return matches.map {
            .init(host: $0[_host], port: $0[_port])
        }
    }
}
