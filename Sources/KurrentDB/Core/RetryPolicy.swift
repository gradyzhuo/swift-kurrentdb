//
//  OperationRetryPolicy.swift
//  KurrentDB
//

import Foundation

/// Retry behaviour applied to operations that fail due to node-level errors.
///
/// When an operation throws a `KurrentError` whose `isNodeFailure` is `true`, the client
/// invalidates the cached node, discovers a new one, and retries up to `maxAttempts` times
/// with exponential backoff and optional jitter between attempts.
///
/// ```swift
/// let settings = ClientSettings.localhost()
///     .operationRetryPolicy(.default)
///
/// let custom = ClientSettings.localhost()
///     .operationRetryPolicy(OperationRetryPolicy(
///         maxAttempts: 5,
///         initialDelay: .milliseconds(200),
///         maxDelay: .seconds(30),
///         multiplier: 1.5,
///         jitter: .full
///     ))
/// ```
public struct OperationRetryPolicy: Sendable {

    /// Total number of attempts including the first try; `1` means no retries.
    public var maxAttempts: Int

    /// Delay before the first retry; `.zero` means retry immediately.
    public var initialDelay: Duration

    /// Upper bound on the delay between retries, capping exponential growth.
    public var maxDelay: Duration

    /// Multiplier applied to the current delay after each retry; `2.0` doubles the delay.
    public var multiplier: Double

    /// Jitter strategy used to spread retry timing across concurrent clients.
    public var jitter: JitterStrategy

    /// Strategy for randomising the retry delay to reduce thundering-herd effects.
    public enum JitterStrategy: Sendable {
        /// No jitter; the computed delay is used as-is.
        case none
        /// Full jitter: actual delay is `delay * random(0.0...1.0)`.
        case full
    }

    /// Creates a retry policy with explicit values for all parameters.
    ///
    /// - Parameters:
    ///   - maxAttempts: Total number of attempts, including the initial try.
    ///   - initialDelay: Delay before the first retry.
    ///   - maxDelay: Maximum delay between retries.
    ///   - multiplier: Exponential backoff multiplier applied after each retry.
    ///   - jitter: Jitter strategy to spread retries across concurrent clients.
    public init(
        maxAttempts: Int,
        initialDelay: Duration,
        maxDelay: Duration,
        multiplier: Double,
        jitter: JitterStrategy
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.jitter = jitter
    }

    /// Sensible default policy: 3 total attempts, 100 ms initial delay, 2× backoff, 10 s cap, full jitter.
    public static let `default` = OperationRetryPolicy(
        maxAttempts: 3,
        initialDelay: .milliseconds(100),
        maxDelay: .seconds(10),
        multiplier: 2.0,
        jitter: .full
    )
}

// MARK: - Duration helpers

extension Duration {
    /// Converts this `Duration` to a `TimeInterval` (Double seconds).
    package var timeInterval: TimeInterval {
        let (sec, atto) = components
        return Double(sec) + Double(atto) / 1_000_000_000_000_000_000.0
    }

    /// Returns a new Duration scaled by `factor`.
    /// Works by converting to total seconds (Double) to avoid Int64 overflow.
    package func multiplied(by factor: Double) -> Duration {
        guard factor > 0 else { return .zero }
        let (sec, atto) = components
        let totalSeconds = Double(sec) + Double(atto) / 1_000_000_000_000_000_000.0
        let scaled = totalSeconds * factor
        let newSec = Int64(scaled)
        let fractional = scaled - Double(newSec)
        let newAtto = Int64(max(0, fractional * 1_000_000_000_000_000_000.0))
        return Duration(secondsComponent: newSec, attosecondsComponent: newAtto)
    }
}

// MARK: - Core retry helper

/// Executes `operation` with retry logic driven by `policy`.
///
/// On each attempt a node is obtained via `selectNode`. If the operation throws
/// a ``KurrentError`` whose `isNodeFailure` is `true` and there are remaining
/// attempts, `invalidate` is called, the backoff delay is applied, and a new
/// node is selected for the next attempt. Any other error propagates immediately.
///
/// Closure parameters use untyped `throws` (matching the `withRethrowingError`
/// convention) because Swift 6 does not support typed throws inside `@Sendable`
/// closures. Non-`KurrentError` throws are wrapped as `.internalClientError`.
///
/// - Parameters:
///   - policy: The retry policy controlling attempts and backoff.
///   - selectNode: Returns the node to use for the next attempt.
///   - invalidate: Called after a node-failure to clear the cached node.
///   - operation: The operation to execute, receiving the selected node.
/// - Returns: The value returned by a successful `operation` call.
/// - Throws: The last `KurrentError` after exhausting all attempts, or any
///   non-node-failure error immediately.
package func withRetry<NodeType: Sendable, T: Sendable>(
    policy: OperationRetryPolicy,
    selectNode: @Sendable () async throws -> NodeType,
    invalidate: @Sendable () async -> Void,
    operation: @Sendable (NodeType) async throws -> T
) async throws(KurrentError) -> T {
    var attempt = 0
    var currentDelay = policy.initialDelay

    while true {
        attempt += 1

        let node: NodeType
        do {
            node = try await selectNode()
        } catch let e as KurrentError {
            throw e
        } catch {
            throw .internalClientError(reason: "withRetry: selectNode failed – \(error)")
        }

        do {
            return try await operation(node)
        } catch let error as KurrentError where error.isNodeFailure && attempt < policy.maxAttempts {
            await invalidate()

            if currentDelay > .zero {
                var delay = currentDelay
                if case .full = policy.jitter {
                    delay = currentDelay.multiplied(by: Double.random(in: 0.0 ... 1.0))
                }
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    // Task was cancelled during backoff sleep.
                    throw KurrentError.connectionClosed
                }
            }

            currentDelay = Swift.min(currentDelay.multiplied(by: policy.multiplier), policy.maxDelay)
        } catch let error as KurrentError {
            throw error
        } catch {
            throw .internalClientError(reason: "withRetry: operation failed – \(error)")
        }
    }
}
