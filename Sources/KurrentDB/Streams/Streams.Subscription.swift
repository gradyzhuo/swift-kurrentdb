//
//  Streams.Subscription.swift
//  KurrentStreams
//
//  Created by Grady Zhuo on 2024/3/23.
//

import GRPCCore
import GRPCEncapsulates
import SwiftProtobuf

extension Streams {
    /// Live subscription to a stream, delivering events as an async throwing stream.
    ///
    /// ``events`` carries the events alone; ``messages`` carries them together with the server's
    /// notifications about the subscription itself (``Message``). Both draw from the same
    /// connection, so iterate one of them, not both.
    public struct Subscription: Sendable {
        /// What the server sends on a subscription: an event, or a notification about the
        /// subscription itself.
        public enum Message: Sendable {
            /// An event of the subscribed stream (or of `$all`).
            case event(ReadEvent)
            /// Everything written before the subscription has been delivered; from here on events
            /// arrive as they are written. Sent again after every ``fellBehind``.
            case caughtUp
            /// Writes have outpaced the consumer, so the subscription is reading history again;
            /// ``caughtUp`` follows once it is current. Sent by KurrentDB 26.2.2 and later; an older
            /// server returns to catch-up silently.
            case fellBehind
            /// A `$all` subscription with a filter has scanned everything up to this position
            /// without a match. Store it as the resume point, so a long stretch without matching
            /// events does not have to be scanned again after a restart.
            case checkpoint(StreamPosition)
        }

        /// Async throwing stream of events received from the server.
        public let events: AsyncThrowingStream<ReadEvent, Error>

        /// Async throwing stream of events and subscription notifications, in the order the
        /// server sent them.
        public let messages: AsyncThrowingStream<Message, Error>

        /// Server-assigned identifier for this subscription, if provided.
        public let subscriptionId: String?

        /// The `ReadReq.Options.ControlOption.compatibility` a subscription declares: the highest
        /// level of server behaviour the client handles. Level 2 is what makes the server send
        /// ``Message/fellBehind``; ``Message/caughtUp`` and checkpoints need no level.
        package static var compatibility: UInt32 { 2 }

        /// Bounded hand-off between the gRPC response handler and the two streams.
        package let handoff: ResponseHandoff<Read.UnderlyingResponse>

        /// `decode` turns a server response into the message the consumer sees, or nil for one
        /// it does not (the confirmation, positions a read would use). It may throw to end the
        /// subscription; the error is mapped like a read's.
        package init(
            handoff: ResponseHandoff<Read.UnderlyingResponse>,
            subscriptionId: String?,
            decode: @escaping @Sendable (Read.UnderlyingResponse) throws -> Message?
        ) {
            self.handoff = handoff
            self.subscriptionId = subscriptionId
            // One hold for both streams: releasing one of them (keeping only `events`, say) must
            // not end the other; the hand-off is cancelled when the last one is released.
            let hold = handoff.hold()
            messages = handoff.makeStream(hold: hold, mapError: serverExceptionOrOriginal, decode)
            events = handoff.makeStream(hold: hold, mapError: serverExceptionOrOriginal) { response in
                if case let .event(readEvent)? = try decode(response) { return readEvent }
                return nil
            }
        }

        /// Cancels the subscription and terminates both streams.
        public func cancel() {
            handoff.cancel()
        }

        /// The notification a non-event response carries, or nil for one the consumer does not see.
        package static func notification(_ content: Read.UnderlyingResponse.OneOf_Content?, usage: String) -> Message? {
            switch content {
            case .caughtUp:
                return .caughtUp
            case .fellBehind:
                return .fellBehind
            case let .checkpoint(checkpoint):
                return .checkpoint(.at(commitPosition: checkpoint.commitPosition, preparePosition: checkpoint.preparePosition))
            case let content?:
                logger.debug("[\(usage)] Received non-event subscription message: \(content)")
                return nil
            case nil:
                return nil
            }
        }
    }
}

extension Streams.Subscription: ConnectionTerminable {
    /// Run when the dedicated connection closes (client shutdown): wakes a producer suspended in
    /// `send` and ends the streams with `connectionClosed`; an element the producer was holding is
    /// dropped. No-op if the hand-off already
    /// ended. Captures only the hand-off, never the subscription (see ``ConnectionTerminable``).
    package var connectionCloseHandler: @Sendable () -> Void {
        { [handoff] in handoff.finish(throwing: KurrentError.connectionClosed) }
    }
}
