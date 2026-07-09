//
//  StreamFilter+Build.swift
//  swift-kurrentdb
//
//  Maps a StreamFilter to the shared gRPC FilterOptions used by both
//  ReadAll and SubscribeAll (they send the same ReadReq.Options).
//

import GRPCEncapsulates

extension StreamFilter {
    /// Builds the gRPC `FilterOptions` message from this filter.
    ///
    /// Shared by `$all` reads and subscriptions, which both carry the filter in
    /// `ReadReq.Options.filter`.
    package func buildFilterOptions() -> EventStore_Client_Streams_ReadReq.Options.FilterOptions {
        .with {
            switch type {
            case .streamName:
                $0.streamIdentifier = .with {
                    if let regex {
                        $0.regex = regex
                    }
                    $0.prefix = prefixes
                }
            case .eventType:
                $0.eventType = .with {
                    if let regex {
                        $0.regex = regex
                    }
                    $0.prefix = prefixes
                }
            }

            switch window {
            case .count:
                $0.count = .init()
            case let .max(value):
                $0.max = value
            }

            $0.checkpointIntervalMultiplier = checkpointIntervalMultiplier
        }
    }
}
