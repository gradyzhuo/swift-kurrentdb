// The article's first switch over a subscription message ("Reading events"), written the
// recommended way: with `@unknown default`. It must build on every toolchain.
import KurrentDB

public func describe(_ message: Streams<SpecifiedStream>.Subscription.Message) -> String {
    switch message {
    case .event:
        return "event"
    case let .caughtUp(caughtUp):
        return "caughtUp \(caughtUp.revision ?? 0)"
    case .fellBehind:
        return "fellBehind"
    case .checkpoint:
        return "checkpoint"
    @unknown default:
        return "unknown"
    }
}
