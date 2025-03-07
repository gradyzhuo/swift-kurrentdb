//
//  StreamIdentifier+Additions.swift
//  KurrentStreams
//
//  Created by 卓俊諺 on 2025/1/24.
//

extension StreamIdentifier {
    func build(options: inout Streams<SpecifiedStream>.Append.UnderlyingRequest.Options) throws {
        options.streamIdentifier = try build()
    }
}
