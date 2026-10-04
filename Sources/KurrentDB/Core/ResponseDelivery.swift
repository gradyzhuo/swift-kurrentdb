//
//  ResponseDelivery.swift
//  KurrentCore
//

/// How a streaming response is delivered to the caller.
///
/// Without a delivery, `read()` returns a stream the SDK has already filled: the RPC is over
/// when `read()` returns, and memory grows with the result. ``ScopedDelivery`` hands the
/// events to a closure as they arrive, with backpressure, and ends the RPC when the closure
/// returns.
public protocol ResponseDelivery: Sendable {}

/// Delivers events to a closure; the RPC lives exactly as long as that closure.
public struct ScopedDelivery: ResponseDelivery {
    public init() {}
}

extension ResponseDelivery where Self == ScopedDelivery {
    /// Events are delivered to a closure with backpressure; the RPC ends when the closure returns.
    public static var scoped: ScopedDelivery { .init() }
}
