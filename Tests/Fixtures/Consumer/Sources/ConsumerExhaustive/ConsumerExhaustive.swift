// The same switch without `@unknown default`. On Swift 6.2.3 and later `Message` is `@nonexhaustive`,
// so this must not compile: check.sh expects exactly that error.
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
    }
}
