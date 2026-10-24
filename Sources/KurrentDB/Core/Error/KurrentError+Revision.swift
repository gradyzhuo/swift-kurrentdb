//
//  KurrentError+Revision.swift
//  swift-kurrentdb
//
//  Created by Grady Zhuo on 2025/4/11.
//

extension KurrentError {
    /// The stream's current revision as the server found it when a version conflict occurred,
    /// or ``noStream`` when the stream does not exist.
    ///
    /// Unlike ``ExpectedRevisionOption``, which echoes the condition the caller chose, this is
    /// what the server observed.
    public enum CurrentRevisionState: Sendable {
        /// The stream does not exist on the server.
        case noStream
        /// The stream exists at the given revision number.
        case revision(UInt64)
    }

    /// The former name of ``CurrentRevisionState``.
    ///
    /// It is the server's observed state, not an option anyone chooses.
    @available(*, deprecated, renamed: "CurrentRevisionState")
    public typealias CurrentRevisionOption = CurrentRevisionState

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
