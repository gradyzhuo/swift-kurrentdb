//
//  MockKurrentDBClient.swift
//  swift-kurrentdb
//

import Synchronization
@testable import KurrentDB

/// A spy implementation of `KurrentDBClientProtocol` for use in unit tests.
///
/// `MockKurrentDBClient` records all factory method calls, letting tests verify that
/// business-logic code uses the correct client factories with the expected arguments.
/// No live KurrentDB server is required — only factory call patterns are tracked.
///
/// ## Thread Safety
///
/// All mutable state is wrapped in a `Mutex<State>` from the `Synchronization` module.
/// This gives the compiler full visibility into the synchronization strategy, so the
/// type can conform to `Sendable` directly — no `@unchecked` annotation is required.
///
/// ## Usage
///
/// ```swift
/// let mock = MockKurrentDBClient()
/// let service = MyService(db: mock)
///
/// service.doWork()
///
/// #expect(mock.streamsCalls.last == .specified("my-stream"))
/// ```
final class MockKurrentDBClient: KurrentDBClientProtocol, Sendable {

    // MARK: - Recorded Call Types

    enum StreamsCall: Equatable, Sendable {
        case specified(String)
        case all
        case multiple
        case generic(String)   // via streams(of:) with a custom target type
    }

    enum PersistentSubscriptionsCall: Equatable, Sendable {
        case all
        case streamGroup(stream: String, group: String)
        case filterGroup(String)
        case filterStream(String)
        case generic(String)   // via persistentSubscriptions(of:)
    }

    enum UsersCall: Equatable, Sendable {
        case all
        case specified(String)
    }

    enum OperationsCall: Equatable, Sendable {
        case scavenge
        case activeScavenge(String)
        case system
        case node
        case generic(String)
    }

    // MARK: - Protected State

    private struct State: Sendable {
        var streamsCalls: [StreamsCall] = []
        var persistentSubscriptionsCalls: [PersistentSubscriptionsCall] = []
        var usersCalls: [UsersCall] = []
        var operationsCalls: [OperationsCall] = []
        var monitoringAccessCount: Int = 0
    }

    // Mutex<State> is Sendable, so the compiler can verify MockKurrentDBClient's
    // Sendable conformance without requiring @unchecked.
    private let state = Mutex(State())

    // MARK: - Public Read-Only Accessors

    var streamsCalls: [StreamsCall] {
        state.withLock { $0.streamsCalls }
    }
    var persistentSubscriptionsCalls: [PersistentSubscriptionsCall] {
        state.withLock { $0.persistentSubscriptionsCalls }
    }
    var usersCalls: [UsersCall] {
        state.withLock { $0.usersCalls }
    }
    var operationsCalls: [OperationsCall] {
        state.withLock { $0.operationsCalls }
    }
    var monitoringAccessCount: Int {
        state.withLock { $0.monitoringAccessCount }
    }

    // MARK: - Backing Infrastructure

    private let selector: NodeSelector

    init() {
        selector = NodeSelector(settings: .localhost())
    }

    // MARK: - KurrentDBClientProtocol — Streams

    func streams<Target: StreamsTarget>(of target: Target) -> Streams<Target> {
        state.withLock { $0.streamsCalls.append(.generic("\(Target.self)")) }
        return Streams(target: target, selector: selector)
    }

    func streams(specified name: String) -> Streams<SpecifiedStream> {
        state.withLock { $0.streamsCalls.append(.specified(name)) }
        return Streams(target: .specified(name), selector: selector)
    }

    var allStreams: Streams<AllStreamsTarget> {
        state.withLock { $0.streamsCalls.append(.all) }
        return Streams(target: .all, selector: selector)
    }

    var multiStreams: Streams<MultiStreamsTarget> {
        state.withLock { $0.streamsCalls.append(.multiple) }
        return Streams(target: .multiple, selector: selector)
    }

    // MARK: - KurrentDBClientProtocol — Persistent Subscriptions

    func persistentSubscriptions<Target: PersistentSubscriptionTarget>(of target: Target) -> PersistentSubscriptions<Target> {
        state.withLock { $0.persistentSubscriptionsCalls.append(.generic("\(Target.self)")) }
        return PersistentSubscriptions(target: target, selector: selector)
    }

    var allPersistentSubscriptions: PersistentSubscriptions<AllPersistentSubscriptionTarget> {
        state.withLock { $0.persistentSubscriptionsCalls.append(.all) }
        return PersistentSubscriptions(target: .all, selector: selector)
    }

    func persistentSubscriptions(stream: String, group: String) -> PersistentSubscriptions<SpecifiedPersistentSubscriptionTarget> {
        state.withLock { $0.persistentSubscriptionsCalls.append(.streamGroup(stream: stream, group: group)) }
        return PersistentSubscriptions(target: .specified(stream: stream, group: group), selector: selector)
    }

    func persistentSubscriptions(filterGroup groupName: String) -> PersistentSubscriptions<AllStreamPersistentSubscriptionTarget> {
        state.withLock { $0.persistentSubscriptionsCalls.append(.filterGroup(groupName)) }
        return PersistentSubscriptions(target: .allStreams(group: groupName), selector: selector)
    }

    func persistentSubscriptions(filterStream stream: String) -> PersistentSubscriptions<FilterStreamPersistentSubscriptionTarget> {
        state.withLock { $0.persistentSubscriptionsCalls.append(.filterStream(stream)) }
        return PersistentSubscriptions(target: .filter(stream: stream), selector: selector)
    }

    // MARK: - KurrentDBClientProtocol — Users

    var users: Users<AllUsersTarget> {
        state.withLock { $0.usersCalls.append(.all) }
        return Users(target: AllUsersTarget(), selector: selector)
    }

    func user(_ loginName: String) -> Users<SpecifiedUserTarget> {
        state.withLock { $0.usersCalls.append(.specified(loginName)) }
        return Users(target: SpecifiedUserTarget(loginName: loginName), selector: selector)
    }

    // MARK: - KurrentDBClientProtocol — Operations

    func operations<Target: OperationsTarget>(of target: Target) -> Operations<Target> {
        let call: OperationsCall = switch target {
        case is ScavengeOperations:   .scavenge
        case let a as ActiveScavenge: .activeScavenge(a.scavengeId)
        case is SystemOperations:     .system
        case is NodeOperations:       .node
        default:                      .generic("\(Target.self)")
        }
        state.withLock { $0.operationsCalls.append(call) }
        return Operations(target: target, selector: selector)
    }

    // MARK: - KurrentDBClientProtocol — Monitoring

    var monitoring: Monitoring {
        state.withLock { $0.monitoringAccessCount += 1 }
        return Monitoring(selector: selector)
    }
}
