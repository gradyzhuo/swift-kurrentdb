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
        /// Async throwing stream of events received from the server.
        public let events: AsyncThrowingStream<ReadEvent, Error>

        /// Async throwing stream of events and subscription notifications, in the order the
        /// server sent them.
        public let messages: AsyncThrowingStream<Message, Error>

        /// Server-assigned identifier for this subscription, if provided.
        public let subscriptionId: String?

        /// The `ReadReq.Options.ControlOption.compatibility` a subscription declares: the highest
        /// level of server behaviour the client handles. Level 2 is what makes the server send
        /// ``Message/fellBehind(_:)``; ``Message/caughtUp(_:)`` and ``Message/checkpoint(_:)`` need no level.
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
            messages = handoff.makeStream(hold: hold, mapError: { mapStreamError($0, usage: "subscribe") }, decode)
            events = handoff.makeStream(hold: hold, mapError: { mapStreamError($0, usage: "subscribe") }) { response in
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
            case let .caughtUp(message):
                let (revision, position) = resumePoint(
                    hasRevision: message.hasStreamRevision, revision: message.streamRevision,
                    hasPosition: message.hasPosition, position: message.position
                )
                return .caughtUp(CaughtUp(
                    timestamp: message.hasTimestamp ? message.timestamp.date : nil,
                    streamRevision: revision,
                    allPosition: position
                ))
            case let .fellBehind(message):
                let (revision, position) = resumePoint(
                    hasRevision: message.hasStreamRevision, revision: message.streamRevision,
                    hasPosition: message.hasPosition, position: message.position
                )
                return .fellBehind(FellBehind(
                    timestamp: message.hasTimestamp ? message.timestamp.date : nil,
                    streamRevision: revision,
                    allPosition: position
                ))
            case let .checkpoint(checkpoint):
                return .checkpoint(Checkpoint(
                    position: .at(commitPosition: checkpoint.commitPosition, preparePosition: checkpoint.preparePosition),
                    timestamp: checkpoint.hasTimestamp ? checkpoint.timestamp.date : nil
                ))
            case let content?:
                logger.debug("[\(usage)] Received non-event subscription message: \(content)")
                return nil
            case nil:
                return nil
            }
        }

        /// The target's own resume point and nothing else, so `==` never differs on the hidden field.
        /// A negative revision is the server's "no position yet" and decodes as nil — deliberately not
        /// `unsignedWireValue`, which throws: a notification must not end the subscription.
        private static func resumePoint(
            hasRevision: Bool,
            revision: Int64,
            hasPosition: Bool,
            position: Read.UnderlyingResponse.Position
        ) -> (UInt64?, StreamPosition?) {
            if Target.self is any SpecifiedStreamTarget.Type {
                return (hasRevision && revision >= 0 ? UInt64(revision) : nil, nil)
            }
            return (nil, hasPosition ? .at(commitPosition: position.commitPosition, preparePosition: position.preparePosition) : nil)
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
