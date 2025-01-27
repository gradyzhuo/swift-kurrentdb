//
//  Selector.swift
//
//
//  Created by Grady Zhuo on 2024/3/23.
//

public enum StreamSelector<T: Sendable>: Sendable {
    case all
    case specified(T)
}
