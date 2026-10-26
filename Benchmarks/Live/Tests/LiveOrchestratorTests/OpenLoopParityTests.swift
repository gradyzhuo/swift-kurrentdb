import Foundation
@testable import LiveBenchCore
import Testing

/// The .NET driver's open loop (`selftest`) against Swift's `runOpenLoop` on the same configurations and synthetic
/// operations: both must account for every index the same way (drop, timeout, failure, drain expiry). No server is
/// needed; the test runs wherever `dotnet` is on `PATH` and builds the driver like the live harness does.
///
/// Every case leaves at least 100 ms between an operation's completion and the boundary that decides its outcome
/// (deadline, drain end), far above both waker's error (< 1 ms) and the .NET millisecond timers, so the counters are
/// compared exactly; no tolerance is needed.
@Suite("Open loop parity: .NET driver vs Swift reference", .serialized)
struct OpenLoopParityTests {
    struct Case: Sendable, CustomStringConvertible {
        var mode: String
        var rate: Double
        var seconds: Double
        var cap: Int
        var deadlineMillis: Int
        var drainMillis: Int
        var stallMillis: Int = 0
        /// scheduled, succeeded, failed, dropped, timedOut
        var expected: [Int]

        var description: String { "\(mode), deadline \(deadlineMillis) ms" + (cap < 256 ? ", over the cap" : "") }
    }

    static let cases: [Case] = [
        Case(mode: "noop", rate: 100, seconds: 0.2, cap: 256, deadlineMillis: 500, drainMillis: 500, expected: [20, 20, 0, 0, 0]),
        Case(mode: "throw", rate: 100, seconds: 0.2, cap: 256, deadlineMillis: 500, drainMillis: 500, expected: [20, 0, 20, 0, 0]),
        // Outstanding at the deadline, cancellation honoured: a timeout, not a failure, although the operation throws
        // a cancellation error once its token fires.
        Case(mode: "stallHonouring", rate: 50, seconds: 0.2, cap: 256, deadlineMillis: 100, drainMillis: 1000, stallMillis: 1000, expected: [10, 0, 0, 0, 10]),
        // The same with the cancellation error raised inline in the token's callback, before the ledger's timeout
        // callback runs (.NET runs cancellation callbacks in reverse registration order).
        Case(mode: "stallHonouringInline", rate: 50, seconds: 0.2, cap: 256, deadlineMillis: 100, drainMillis: 1000, stallMillis: 1000, expected: [10, 0, 0, 0, 10]),
        // Cancellation ignored: recorded as a timeout at the deadline, the late completion is ignored.
        Case(mode: "stallIgnoring", rate: 50, seconds: 0.2, cap: 256, deadlineMillis: 100, drainMillis: 1000, stallMillis: 1000, expected: [10, 0, 0, 0, 10]),
        // Completes 300 ms before its deadline: a success.
        Case(mode: "stallHonouring", rate: 50, seconds: 0.2, cap: 256, deadlineMillis: 500, drainMillis: 1000, stallMillis: 200, expected: [10, 10, 0, 0, 0]),
        // A completion instant past the deadline is a timeout even though the operation returned before any timer.
        Case(mode: "instantPastDeadline", rate: 100, seconds: 0.2, cap: 256, deadlineMillis: 500, drainMillis: 500, expected: [20, 0, 0, 0, 20]),
        // Cap 10 of 50 operations that never finish within the window: 40 drops, and the 10 outstanding expire at the
        // drain end (deadline 5 s is after it).
        Case(mode: "stallIgnoring", rate: 100, seconds: 0.5, cap: 10, deadlineMillis: 5000, drainMillis: 200, stallMillis: 10_000, expected: [50, 0, 0, 40, 10]),
    ]

    @Test(.enabled(if: dotnetAvailable), arguments: cases)
    func dotnetOpenLoopAccountsLikeSwift(_ c: Case) async throws {
        // The .NET side (build, then the driver process) blocks while it runs, so it runs on a dispatch thread: a
        // blocked cooperative thread would starve the Swift open loop of this or a concurrently running test.
        let dotnet = try await offCooperativePool { try dotnetCounters(c) }
        let swift = await swiftCounters(c)
        #expect(swift == c.expected, "swift \(c)")
        #expect(dotnet == c.expected, "dotnet \(c)")
        #expect(swift == dotnet)
    }

    private func swiftCounters(_ c: Case) async -> [Int] {
        let config = OpenLoopConfig(
            rate: c.rate, duration: .milliseconds(Int(c.seconds * 1000)), inFlightCap: c.cap,
            deadline: .milliseconds(c.deadlineMillis), drain: .milliseconds(c.drainMillis)
        )
        let stall = Duration.milliseconds(c.stallMillis)
        let deadline = Duration.milliseconds(c.deadlineMillis)
        let r = await runOpenLoop(config, clock: ContinuousClock()) { _ -> ContinuousClock.Instant? in
            switch c.mode {
            case "throw":
                throw HarnessError("synthetic failure")
            case "stallHonouring", "stallHonouringInline":
                try await Task.sleep(for: stall)
            case "stallIgnoring":
                // A detached task is not cancelled with the operation.
                await Task.detached { try? await Task.sleep(for: stall) }.value
            case "instantPastDeadline":
                return ContinuousClock.now.advanced(by: deadline + .milliseconds(10))
            default:
                break
            }
            return nil
        }
        return [r.scheduled, r.succeeded, r.failed, r.dropped, r.timedOut]
    }

    private nonisolated func dotnetCounters(_ c: Case) throws -> [Int] {
        let dll = try DotNetDriverBuild.dll()
        let output = try runTool("dotnet", [
            dll.path, "selftest", "--mode", c.mode, "--rate", "\(c.rate)", "--seconds", "\(c.seconds)",
            "--cap", "\(c.cap)", "--deadline-ms", "\(c.deadlineMillis)", "--drain-ms", "\(c.drainMillis)",
            "--stall-ms", "\(c.stallMillis)",
        ])
        struct Counters: Decodable { var scheduled, succeeded, failed, dropped, timedOut: Int }
        let r = try JSONDecoder().decode(Counters.self, from: Data(output.utf8))
        return [r.scheduled, r.succeeded, r.failed, r.dropped, r.timedOut]
    }
}

/// Runs blocking `work` on a dispatch thread and awaits its result.
private func offCooperativePool<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async { continuation.resume(with: Result { try work() }) }
    }
}

/// `dotnet` is on `PATH` (the .NET tests skip without it).
let dotnetAvailable = (try? runTool("dotnet", ["--version"])) != nil
