import Foundation
import SwiftProtobuf
import Testing
import _GRPCProtobufGenerated
@testable import KurrentDB

@Suite("Subscription message decoding")
struct SubscriptionMessageDecodingTests {
    typealias Content = EventStore_Client_Streams_ReadResp.OneOf_Content
    typealias StreamSubscription = Streams<SpecifiedStream>.Subscription
    typealias AllSubscription = Streams<AllStreamsTarget>.Subscription
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    @Test func caughtUpForStreamTargetCarriesTimestampAndRevision() {
        let content = Content.caughtUp(.with { $0.timestamp = .init(date: date); $0.streamRevision = 5 })
        guard case let .caughtUp(c)? = StreamSubscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(c.timestamp == date)
        #expect(c.revision == 5)
        #expect(c == StreamSubscription.CaughtUp(timestamp: date, revision: 5))
    }

    // `client.streams(of: "orders")` is `Streams<String>`, and `ProjectionStream` reads a projection's
    // stream: both are stream targets, so both get the revision and never the $all position.
    @Test func everyStreamTargetDecodesTheRevision() {
        let content = Content.caughtUp(.with { $0.streamRevision = 5; $0.position = .with { $0.commitPosition = 10; $0.preparePosition = 9 } })
        guard case let .caughtUp(s)? = Streams<String>.Subscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(s == Streams<String>.Subscription.CaughtUp(revision: 5))
        guard case let .caughtUp(p)? = Streams<ProjectionStream>.Subscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(p == Streams<ProjectionStream>.Subscription.CaughtUp(revision: 5))
    }

    @Test func caughtUpWithoutFieldsHasNilTimestampAndRevision() {
        guard case let .caughtUp(c)? = StreamSubscription.notification(.caughtUp(.init()), usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(c.timestamp == nil)
        #expect(c.revision == nil)
    }

    @Test func negativeStreamRevisionDecodesAsNil() {
        let content = Content.caughtUp(.with { $0.streamRevision = -1 })
        guard case let .caughtUp(c)? = StreamSubscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(c.revision == nil)
    }

    @Test func streamTargetIgnoresAllPosition() {
        let content = Content.caughtUp(.with { $0.position = .with { $0.commitPosition = 10; $0.preparePosition = 9 } })
        guard case let .caughtUp(c)? = StreamSubscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(c == StreamSubscription.CaughtUp())
    }

    @Test func allTargetCarriesPosition() {
        let content = Content.caughtUp(.with { $0.timestamp = .init(date: date); $0.position = .with { $0.commitPosition = 10; $0.preparePosition = 9 } })
        guard case let .caughtUp(c)? = AllSubscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(c.position == .at(commitPosition: 10, preparePosition: 9))
        #expect(c == AllSubscription.CaughtUp(timestamp: date, position: .at(commitPosition: 10, preparePosition: 9)))
    }

    @Test func allTargetIgnoresStreamRevision() {
        let content = Content.caughtUp(.with { $0.streamRevision = 5 })
        guard case let .caughtUp(c)? = AllSubscription.notification(content, usage: "t") else { Issue.record("not caughtUp"); return }
        #expect(c == AllSubscription.CaughtUp())
    }

    @Test func fellBehindDecodesLikeCaughtUp() {
        let content = Content.fellBehind(.with { $0.timestamp = .init(date: date); $0.streamRevision = 7 })
        guard case let .fellBehind(f)? = StreamSubscription.notification(content, usage: "t") else { Issue.record("not fellBehind"); return }
        #expect(f == StreamSubscription.FellBehind(timestamp: date, revision: 7))
        let all = Content.fellBehind(.with { $0.position = .with { $0.commitPosition = 3; $0.preparePosition = 3 } })
        guard case let .fellBehind(g)? = AllSubscription.notification(all, usage: "t") else { Issue.record("not fellBehind"); return }
        #expect(g == AllSubscription.FellBehind(position: .at(commitPosition: 3)))
    }

    @Test func checkpointCarriesPositionAndTimestamp() {
        let content = Content.checkpoint(.with { $0.commitPosition = 7; $0.preparePosition = 6; $0.timestamp = .init(date: date) })
        guard case let .checkpoint(cp)? = AllSubscription.notification(content, usage: "t") else { Issue.record("not checkpoint"); return }
        #expect(cp == AllSubscription.Checkpoint(position: .at(commitPosition: 7, preparePosition: 6), timestamp: date))
        guard case let .checkpoint(old)? = AllSubscription.notification(.checkpoint(.with { $0.commitPosition = 1; $0.preparePosition = 1 }), usage: "t") else { Issue.record("not checkpoint"); return }
        #expect(old.timestamp == nil)
    }

    @Test func levelOneFramesAreDropped() {
        // Message is not Equatable (ReadEvent is not), so compare against nil by pattern.
        for (name, dropped) in [
            ("firstStreamPosition", StreamSubscription.notification(.firstStreamPosition(1), usage: "t")),
            ("lastStreamPosition", StreamSubscription.notification(.lastStreamPosition(2), usage: "t")),
            ("nil content", StreamSubscription.notification(nil, usage: "t")),
        ] where dropped != nil {
            Issue.record("\(name) was delivered")
        }
        if AllSubscription.notification(.lastAllStreamPosition(.with { $0.commitPosition = 3; $0.preparePosition = 3 }), usage: "t") != nil {
            Issue.record("lastAllStreamPosition was delivered")
        }
    }

    @Test func descriptionNamesTheTargetsOwnField() {
        #expect(StreamSubscription.CaughtUp(revision: 5).description == "CaughtUp(timestamp: nil, revision: 5)")
        #expect(AllSubscription.CaughtUp(position: .at(commitPosition: 10, preparePosition: 9)).description == "CaughtUp(timestamp: nil, position: 10/9)")
        #expect(StreamSubscription.FellBehind().description == "FellBehind(timestamp: nil, revision: nil)")
    }

    @Test func payloadsAreHashable() {
        let set: Set<AllSubscription.Checkpoint> = [.init(position: .at(commitPosition: 1)), .init(position: .at(commitPosition: 1))]
        #expect(set.count == 1)
        #expect(Set([StreamSubscription.CaughtUp(revision: 1), .init(revision: 1)]).count == 1)
    }
}
