//
//  ContentType.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/6/2.
//

import Foundation

/// MIME content type for event data payloads.
public enum ContentType: String, Codable, Sendable {
    /// Content type is not specified or unrecognised.
    case unknown
    /// JSON-encoded payload (`application/json`).
    case json = "application/json"
    /// Raw binary payload (`application/octet-stream`).
    case binary = "application/octet-stream"
}
