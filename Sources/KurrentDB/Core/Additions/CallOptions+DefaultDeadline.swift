//
//  CallOptions+DefaultDeadline.swift
//  KurrentCore
//

import GRPCCore

extension CallOptions {
    /// Returns these options with ``ClientSettings/defaultDeadline`` as the timeout when the
    /// caller set none.
    ///
    /// Applied to calls that complete before they return — single responses, appends and the
    /// buffered reads — not to subscriptions or lazy reads, whose lifetime is the caller's
    /// iteration. A lazy read is bounded differently: the default deadline bounds establishing it —
    /// node selection to the server's first response — as one budget (`withEstablishmentBudget`);
    /// iteration is unbounded. For the calls this applies to, a timeout set on the options themselves
    /// wins; for a lazy read both apply, and whichever expires first ends establishment (the options
    /// timeout then keeps bounding the iteration). `.max` (the default) and non-positive values mean
    /// no deadline.
    package func applyingDefaultDeadline(from settings: ClientSettings) -> CallOptions {
        guard timeout == nil, settings.defaultDeadline != .max, settings.defaultDeadline > 0 else {
            return self
        }
        var options = self
        options.timeout = .milliseconds(settings.defaultDeadline)
        return options
    }
}
