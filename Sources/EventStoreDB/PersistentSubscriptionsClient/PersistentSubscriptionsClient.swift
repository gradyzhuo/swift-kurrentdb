//
//  PersistentSubscriptionsClient.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPC
import GRPCEncapsulates

public struct PersistentSubscriptionsClient: GRPCConcreteClient {
    public typealias UnderlyingClient = EventStore_Client_PersistentSubscriptions_PersistentSubscriptionsAsyncClient

    public private(set) var channel: GRPCChannel
    public var callOptions: CallOptions

    public init(channel: GRPCChannel, callOptions: CallOptions) {
        self.channel = channel
        self.callOptions = callOptions
    }
}

extension PersistentSubscriptionsClient {
    public enum StreamSelection {
        case all(position: Cursor<StreamClient.Read.Position>, filterOption: StreamClient.FilterOption? = nil)
        case specified(identifier: Stream.Identifier, revision: Cursor<UInt64>)

        public static func specified(identifier: Stream.Identifier) -> Self {
            .specified(identifier: identifier, revision: .end)
        }

        public static func specified(streamName: String, revision _: Cursor<UInt64> = .end) -> Self {
            .specified(identifier: .init(name: streamName), revision: .end)
        }
    }

    public enum SystemConsumerStrategy: RawRepresentable, Sendable {
        public typealias RawValue = String

        /// Distributes events to a single client until the bufferSize is reached.
        /// After which the next client is selected in a round robin style,
        /// and the process is repeated.
        case dispatchToSingle

        /// Distributes events to all clients evenly. If the client buffer-size
        /// is reached the client is ignored until events are
        /// acknowledged/not acknowledged.
        case roundRobin

        /// For use with an indexing projection such as the system $by_category
        /// projection. Event Store inspects event for its source stream id,
        /// hashing the id to one of 1024 buckets assigned to individual clients.
        /// When a client disconnects it's buckets are assigned to other clients.
        /// When a client connects, it is assigned some of the existing buckets.
        /// This naively attempts to maintain a balanced workload.
        /// The main aim of this strategy is to decrease the likelihood of
        /// concurrency and ordering issues while maintaining load balancing.
        /// This is not a guarantee, and you should handle the usual ordering
        /// and concurrency issues.
        case pinned

        case pinnedByCorrelation

        case custom(String)

        public var rawValue: String {
            switch self {
            case .dispatchToSingle:
                "DispatchToSingle"
            case .roundRobin:
                "RoundRobin"
            case .pinned:
                "Pinned"
            case .pinnedByCorrelation:
                "PinnedByCorrelation"
            case let .custom(value):
                value
            }
        }

        public init?(rawValue: String) {
            switch rawValue {
            case Self.dispatchToSingle.rawValue:
                self = .dispatchToSingle
            case Self.roundRobin.rawValue:
                self = .roundRobin
            case Self.pinned.rawValue:
                self = .pinned
            case Self.pinnedByCorrelation.rawValue:
                self = .pinnedByCorrelation
            default:
                self = .custom(rawValue)
            }
        }
    }
}

extension PersistentSubscriptionsClient {
    // MARK: - Create Action

    func createToStream(streamName: String, groupName: String, options: Create.ToStream.Options) async throws {
        let handler: Create.ToStream = .init(streamIdentifier: .init(name: streamName), groupName: groupName, options: options)

        let request = try handler.build()

        try await handler.handle(response: underlyingClient.create(request))
    }

    func createToAll(groupName: String, options: PersistentSubscriptionsClient.Create.ToAll.Options) async throws {
        let handler: PersistentSubscriptionsClient.Create.ToAll = .init(groupName: groupName, options: options)

        let request = try handler.build()
        try await handler.handle(response: underlyingClient.create(request))
    }

    // MARK: - Update Action

    func updateToStream(identifier: Stream.Identifier, groupName: String, options: Update.ToStream.Options) async throws {
        let handler = Update.ToStream(streamIdentifier: identifier, groupName: groupName, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
    }

    func updateToAll(identifier _: Stream.Identifier, groupName: String, options: Update.ToAll.Options) async throws {
        let handler = Update.ToAll(groupName: groupName, options: options)
        let request = try handler.build()
        try await handler.handle(response: underlyingClient.update(request))
    }

    // MARK: - Delete Actions

    func deleteOn(stream: Selector<Stream.Identifier>, groupName: String) async throws {
        let handler = Delete(streamSelection: stream, groupName: groupName)
        let request = try handler.build()

        try await handler.handle(response: underlyingClient.delete(request))
    }

    // MARK: - Read Actions

    func subscribeTo(_ streamSelection: Selector<Stream.Identifier>, groupName: String, options: Read.Options) async throws -> Subscription {
        let handler = Read(streamSelection: streamSelection, groupName: groupName, options: options)
        let requests = try handler.build()

        let getSubscriptionCall = underlyingClient.makeReadCall()
        try await getSubscriptionCall.requestStream.send(requests)

        return try await .init(readCall: getSubscriptionCall)
    }

    // MARK: - GetInfo Action

    func getInfo(stream streamSelection: Selector<Stream.Identifier>, groupName: String) async throws -> GetInfo.SubscriptionInfo {
        let handler = GetInfo(streamSelection: streamSelection, groupName: groupName)
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.getInfo(request))

        return response.subscriptionInfo
    }

    // MARK: - ReplayParked Action

    func replayParkedMessages(stream streamSelection: Selector<Stream.Identifier>, groupName: String, options: ReplayParked.Options) async throws {
        let handler = ReplayParked(streamSelection: streamSelection, groupName: groupName, options: options)
        let request = try handler.build()

        try await handler.handle(response: underlyingClient.replayParked(request))
    }

    func replayParkedMessages(stream streamSelection: Selector<Stream.Identifier>, groupName: String, configure: (_ options: ReplayParked.Options) -> ReplayParked.Options) async throws {
        try await replayParkedMessages(stream: streamSelection, groupName: groupName, options: configure(.init()))
    }

    // MARK: - List Action

    func list(stream: Selector<Stream.Identifier>) async throws -> [GetInfo.SubscriptionInfo] {
        let options = try List.Options.listForStream(stream)

        let handler = List(options: options)
        let request = try handler.build()
        let response = try await handler.handle(response: underlyingClient.list(request))
        return response.subscriptions
    }

    // MARK: - Restart Subsystem Action

    @MainActor
    func restartSubsystem() async throws {
        let handler = RestartSubsystem()
        try await handler.handle(response: underlyingClient.restartSubsystem(handler.build(), callOptions: callOptions))
    }
}
