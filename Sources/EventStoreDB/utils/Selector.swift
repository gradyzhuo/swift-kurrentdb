//
//  Selector.swift
//
//
//  Created by 卓俊諺 on 2024/3/23.
//

import Foundation

public enum Selector<T> {
    case all
    case specified(T)
}

extension Selector where T == Stream.Identifier {
    public static func specified(streamName: String) -> Self {
        .specified(.init(name: streamName))
    }
}
