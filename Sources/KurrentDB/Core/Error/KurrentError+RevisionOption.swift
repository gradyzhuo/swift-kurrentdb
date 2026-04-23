//
//  KurrentError+RevisionOption.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/11.
//

extension KurrentError {
    /// The actual stream revision returned by the server when a version conflict occurs.
    public enum CurrentRevisionOption: Sendable {
        /// The stream does not exist on the server.
        case noStream
        /// The stream exists at the given revision number.
        case revision(UInt64)
    }

    /// The revision expectation provided by the caller when appending events.
    public enum ExpectedRevisionOption: Sendable {
        /// No revision constraint — append succeeds regardless of current state.
        case any
        /// The stream must already exist; fails if the stream has not been created.
        case streamExists
        /// The stream must not exist; fails if the stream already has events.
        case noStream
        /// The stream must be at exactly this revision number.
        case revision(UInt64)
    }
}
