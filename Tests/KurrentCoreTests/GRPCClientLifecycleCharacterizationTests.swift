//
//  GRPCClientLifecycleCharacterizationTests.swift
//  swift-kurrentdb
//
// Pins the connection lifecycle behaviour of grpc-swift 2. These tests do not check KurrentDB's
// logic; they record third-party behaviour we rely on, so they fail first if upstream changes.
//
// Established fact: for a target that cannot be reached, `runConnections()` does not fail fast.
// It hangs without end, neither throwing nor returning, so there is no error and nothing
// is "swallowed". The only way to end it is to cancel the Task running it;
// after the cancel the call itself returns normally (it throws neither CancellationError nor
// any other error), and the client is stopped. So this file does not check that it throws
// (it does not), but that a cancel ends it, that it ends by returning normally, and that the
// client is stopped afterwards.
//

import Testing
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import KurrentDB

@Suite("GRPCClient connection lifecycle characterization", .serialized, .timeLimit(.minutes(1)))
struct GRPCClientLifecycleCharacterizationTests {

    /// A client for an address that can never be reached (TEST-NET-1, reserved by RFC 5737, not routable).
    /// It uses the repository's `Endpoint.target` and `.http2NIOPosix`, built the way
    /// `ConnectionProvider.makeClient(for:)` builds it.
    private func unreachableTransport() throws -> HTTP2ClientTransport.Posix {
        let endpoint = Endpoint(host: "192.0.2.1", port: 2113)
        return try .http2NIOPosix(
            target: endpoint.target,
            transportSecurity: .plaintext
        )
    }

    /// `runConnections()` on a target that cannot be reached waits without end. That cannot be
    /// asserted without a wall clock ("never ends" is not a condition `#expect` can
    /// check). The only verified way to end it is to cancel the Task running it, which
    /// is also what grpc-swift's documentation says (`GRPCClient.swift:212`):
    /// "If you need to abruptly stop all work you should cancel the task
    /// executing this method."
    ///
    /// This test pins three things, each done within milliseconds (no time limit decides the result):
    /// 1. A cancel unblocks it: `task.value` returns instead of hanging.
    /// 2. The cancelled `runConnections()` call itself returns normally, throwing neither
    ///    `CancellationError` nor any other error (confirmed by running a probing test
    ///    three times, with the same result). This matters to the production fix: a caller
    ///    cannot tell "ended by a cancel" with `catch is CancellationError`, because
    ///    nothing is thrown.
    /// 3. After the cancel the client is stopped: a second `runConnections()`
    ///    always throws, which shows a client runs only once.
    @Test("After the connection Task is cancelled the call returns normally, without throwing, and the client is stopped")
    func cancellingConnectionTaskStopsClient() async throws {
        let client = GRPCClient(transport: try unreachableTransport())
        let task = Task { try await client.runConnections() }
        task.cancel()

        // The cancelled first call: returns normally, without throwing (verified 3 times with a probing test, same result).
        try await task.value

        // Running again must throw: a client runs only once, and the cancel has stopped it.
        await #expect(throws: (any Error).self) {
            try await client.runConnections()
        }
    }
}
