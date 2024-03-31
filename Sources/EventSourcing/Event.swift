//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/4/1.
//

import Foundation

public protocol Event: Codable, CustomStringConvertible {
    static var eventName: String { get }
    var updated: Date { get }
}
