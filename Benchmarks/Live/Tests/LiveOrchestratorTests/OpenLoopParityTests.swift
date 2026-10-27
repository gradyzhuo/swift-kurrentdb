import Foundation
@testable import LiveBenchCore
import Testing

/// The .NET driver's open loop (`selftest`) against Swift's `runOpenLoop` on the same configurations and synthetic
/// operations: both must account for every index the same way (drop, timeout, failure, drain expiry). No server is
/// needed; the test runs wherever `dotnet` is on `PATH` and builds the driver like the live harness does.
///
/// Every case leaves at least 100 ms between an operation's completion and the boundary that decides its outcome
/// (deadline, drain end), far above both waker's error (< 1 ms) and the .NET millisecond timers, so the counters are
/// compared exactly; no tolerance is needed. `scheduledSecondHalf` depends only on the schedule and is compared in
/// every case; the backlog samples (minima over trailing spans of observations, `BacklogWindows`) only where every
/// completion is at least 100 ms from every observation (`backlog`), since elsewhere they depend on when completions
/// land relative to the launches.
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
        /// `stallTail`: the first index that stalls.
        var stallFrom: Int = 0
        /// scheduled, succeeded, failed, dropped, timedOut
        var expected: [Int]
        var backlog: BacklogSamples? = nil
        /// Expected `scheduledSecondHalf` where the case pins the schedule's rounding.
        var secondHalf: Int? = nil

        var description: String {
            "\(mode)" + (mode == "stallTail" ? " from \(stallFrom)" : "") + ", deadline \(deadlineMillis) ms" + (cap < 256 ? ", over the cap" : "")
        }
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
        Case(
            mode: "stallIgnoring", rate: 100, seconds: 0.5, cap: 10, deadlineMillis: 5000, drainMillis: 200,
            stallMillis: 10_000,
            expected: [50, 0, 0, 40, 10], backlog: BacklogSamples(atMidpoint: 1, atEnd: 10, scheduledSecondHalf: 25)
        ),
        // Fractional offsets: index 3 is due at 3 × 33,333,333.33… ns, which rounds to exactly 100 ms, half the
        // window, so it is the midpoint index (unrounded it would be index 4). Pins Swift's `.rounded()` against
        // .NET's `MidpointRounding.AwayFromZero`.
        Case(
            mode: "noop", rate: 30, seconds: 0.2, cap: 256, deadlineMillis: 500, drainMillis: 500,
            expected: [6, 6, 0, 0, 0], secondHalf: 3
        ),
        // Nothing completes within the window. A 0.4 s window has 0.2 s spans: the midpoint span (indices 0-10) has
        // its minimum at index 0 (1), the end span (indices 10-19) at index 10 (11).
        Case(
            mode: "stallIgnoring", rate: 50, seconds: 0.4, cap: 256, deadlineMillis: 5000, drainMillis: 200,
            stallMillis: 10_000,
            expected: [20, 0, 0, 0, 20], backlog: BacklogSamples(atMidpoint: 1, atEnd: 11, scheduledSecondHalf: 10)
        ),
        // A stall in the last half second (indices 15-19 of 20, each 600 ms): the backlog peaks at 5 when scheduling
        // ends, but the end span (1-2 s, indices 10-19) also holds no-ops with a backlog of 1, so both minima are 1.
        Case(
            mode: "stallTail", rate: 10, seconds: 2, cap: 256, deadlineMillis: 2000, drainMillis: 1000,
            stallMillis: 600, stallFrom: 15,
            expected: [20, 20, 0, 0, 0], backlog: BacklogSamples(atMidpoint: 1, atEnd: 1, scheduledSecondHalf: 10)
        ),
        // Nothing completes within a 3 s window, so each minimum is its span's first observation: index 5, exactly
        // 0.5 s (the midpoint index 15 minus 1 s), and index 20, exactly 2 s (the window's end minus 1 s).
        Case(
            mode: "stallIgnoring", rate: 10, seconds: 3, cap: 256, deadlineMillis: 5000, drainMillis: 200,
            stallMillis: 10_000,
            expected: [30, 0, 0, 0, 30], backlog: BacklogSamples(atMidpoint: 6, atEnd: 21, scheduledSecondHalf: 15)
        ),
    ]

    @Test(.enabled(if: dotnetAvailable), arguments: cases)
    func dotnetOpenLoopAccountsLikeSwift(_ c: Case) async throws {
        // The .NET side (build, then the driver process) blocks while it runs, so it runs on a dispatch thread: a
        // blocked cooperative thread would starve the Swift open loop of this or a concurrently running test.
        let dotnet = try await offCooperativePool { try dotnetCounters(c) }
        let swift = await swiftCounters(c)
        #expect(swift.counters == c.expected, "swift \(c)")
        #expect(dotnet.counters == c.expected, "dotnet \(c)")
        #expect(swift.counters == dotnet.counters)
        #expect(swift.backlog != nil && dotnet.backlog != nil, "\(c)")
        #expect(swift.backlog?.scheduledSecondHalf == dotnet.backlog?.scheduledSecondHalf, "\(c)")
        if let secondHalf = c.secondHalf {
            #expect(swift.backlog?.scheduledSecondHalf == secondHalf, "swift \(c)")
            #expect(dotnet.backlog?.scheduledSecondHalf == secondHalf, "dotnet \(c)")
        }
        if let backlog = c.backlog {
            #expect(swift.backlog == backlog, "swift \(c)")
            #expect(dotnet.backlog == backlog, "dotnet \(c)")
        }
    }

    /// The .NET `floor` prints the fields of `HarnessFloor`, which the Swift driver's `floor` encodes and the
    /// orchestrator decodes for both.
    @Test(.enabled(if: dotnetAvailable))
    func dotnetFloorPrintsTheSharedFields() async throws {
        let output = try await offCooperativePool {
            try runTool("dotnet", [try DotNetDriverBuild.dll().path, "floor", "--rate", "1000", "--seconds", "0.2", "--warmup", "0.1"])
        }
        let object = try #require(try JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
        #expect(Set(object.keys) == HarnessFloor.fieldNames)
        let floor = try JSONDecoder().decode(HarnessFloor.self, from: Data(output.utf8))
        #expect(floor.scheduled == 200 && floor.succeeded == 200)
        #expect(floor.maxRssBytes > 0)
    }

    /// CI sets `LIVE_BENCH_REQUIRE_DOTNET=1`: there a missing `dotnet` fails instead of skipping the .NET tests.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["LIVE_BENCH_REQUIRE_DOTNET"] == "1"))
    func dotnetIsOnPathWhereRequired() {
        #expect(dotnetAvailable, "LIVE_BENCH_REQUIRE_DOTNET=1 but `dotnet --version` failed: the .NET parity tests would be skipped")
    }

    /// Outcome counters (scheduled, succeeded, failed, dropped, timedOut) and backlog samples of one run.
    struct Observed {
        var counters: [Int]
        var backlog: BacklogSamples?
    }

    private func swiftCounters(_ c: Case) async -> Observed {
        let config = OpenLoopConfig(
            rate: c.rate, duration: .milliseconds(Int(c.seconds * 1000)), inFlightCap: c.cap,
            deadline: .milliseconds(c.deadlineMillis), drain: .milliseconds(c.drainMillis)
        )
        let stall = Duration.milliseconds(c.stallMillis)
        let deadline = Duration.milliseconds(c.deadlineMillis)
        let r = await runOpenLoop(config, clock: ContinuousClock()) { index -> ContinuousClock.Instant? in
            switch c.mode {
            case "throw":
                throw HarnessError("synthetic failure")
            case "stallHonouring", "stallHonouringInline":
                try await Task.sleep(for: stall)
            case "stallIgnoring":
                // A detached task is not cancelled with the operation.
                await Task.detached { try? await Task.sleep(for: stall) }.value
            case "stallTail":
                if index >= c.stallFrom { try await Task.sleep(for: stall) }
            case "instantPastDeadline":
                return ContinuousClock.now.advanced(by: deadline + .milliseconds(10))
            default:
                break
            }
            return nil
        }
        return Observed(counters: [r.scheduled, r.succeeded, r.failed, r.dropped, r.timedOut], backlog: r.backlog)
    }

    private nonisolated func dotnetCounters(_ c: Case) throws -> Observed {
        let dll = try DotNetDriverBuild.dll()
        let output = try runTool("dotnet", [
            dll.path, "selftest", "--mode", c.mode, "--rate", "\(c.rate)", "--seconds", "\(c.seconds)",
            "--cap", "\(c.cap)", "--deadline-ms", "\(c.deadlineMillis)", "--drain-ms", "\(c.drainMillis)",
            "--stall-ms", "\(c.stallMillis)", "--stall-from", "\(c.stallFrom)",
        ])
        struct Counters: Decodable {
            var scheduled, succeeded, failed, dropped, timedOut: Int
            var backlogAtMidpoint, backlogAtEnd, scheduledSecondHalf: Int?

            var backlog: BacklogSamples? {
                guard let backlogAtMidpoint, let backlogAtEnd, let scheduledSecondHalf else { return nil }
                return BacklogSamples(
                    atMidpoint: backlogAtMidpoint, atEnd: backlogAtEnd, scheduledSecondHalf: scheduledSecondHalf
                )
            }
        }
        let r = try JSONDecoder().decode(Counters.self, from: Data(output.utf8))
        return Observed(counters: [r.scheduled, r.succeeded, r.failed, r.dropped, r.timedOut], backlog: r.backlog)
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
