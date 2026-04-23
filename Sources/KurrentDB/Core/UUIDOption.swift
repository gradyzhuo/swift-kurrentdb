//
//  UUIDOption.swift
//  KurrentCore
//
//  Created by Grady Zhuo on 2024/6/23.
//
import Foundation

/// Wire format used to encode UUIDs in gRPC messages.
public enum UUIDOption: Sendable {
    /// Encodes the UUID as two 64-bit integers (most-significant and least-significant bits).
    case structured
    /// Encodes the UUID as a lowercase hyphenated string.
    case string
}
