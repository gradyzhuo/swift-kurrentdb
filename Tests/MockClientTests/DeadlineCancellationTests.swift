//
//  DeadlineCancellationTests.swift
//  MockClientTests
//

import GRPCCore
import Testing
@testable import KurrentDB

@Suite("Deadline cancellation mapping")
struct DeadlineCancellationTests {
    @Test("An unrequested CancellationError becomes deadlineExceeded")
    func mapsWhenTaskNotCancelled() async {
        let mapped = await Task { deadlineOrOriginal(CancellationError()) }.value
        let rpcError = mapped as? RPCError
        #expect(rpcError?.code == .deadlineExceeded)
    }

    @Test("A CancellationError inside a cancelled task passes through")
    func keepsWhenTaskCancelled() async {
        let mapped = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return deadlineOrOriginal(CancellationError())
        }.value
        #expect(mapped is CancellationError)
    }

    @Test("Other errors pass through unchanged")
    func keepsOtherErrors() async {
        let (rpc, kurrent) = await Task {
            (deadlineOrOriginal(RPCError(code: .unavailable, message: "x")),
             deadlineOrOriginal(KurrentError.connectionClosed))
        }.value
        #expect((rpc as? RPCError)?.code == .unavailable)
        if case .connectionClosed? = kurrent as? KurrentError {} else {
            Issue.record("expected KurrentError.connectionClosed, got \(kurrent)")
        }
    }

    @Test("HandlerCancellation.mark is observable")
    func flagIsObservable() {
        let flag = HandlerCancellation()
        #expect(!flag.isMarked)
        flag.mark()
        #expect(flag.isMarked)
    }
}
