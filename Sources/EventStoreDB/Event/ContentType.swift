//
//  ContentType.swift
//
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation

public enum ContentType: String, Codable, Sendable {
    case unknown
    case json = "application/json"
    case binary = "application/octet-stream"
}
