//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/3/22.
//

import Foundation
import SwiftProtobuf
import GRPCSupport

public protocol PersistentSubscriptionsGRPCSettings: SwiftProtobuf.Message {
    static func make(settings: PersistentSubscriptionsClient.Settings) -> Self
}


extension PersistentSubscriptionsClient {
    
    public struct Settings{
        
        public var resolveLink: Bool = false

        /// Whether or not in depth latency statistics should be tracked on this
        /// subscription.
        public var extraStatistics: Bool = false

        /// The amount of time (ms) after which a message should be considered to be
        /// timeout and retried.
        public var messageTimeout: TimeSpan = .ms(30)

        /// The maximum number of retries (due to timeout) before a message get
        /// considered to be parked.
        public var maxRetryCount: Int32 = 10
        
        public var checkpointCount: ClosedRange<Int32> = 10 ... 1000
        
        public var maxSubscriberCount: Int32 = 0

        /// The size of the buffer listening to live messages as they happen.
        public var liveBufferSize: Int32 = 500

        /// The number of events read at a time when paging in history.
        public var readBatchSize: Int32 = 20

        /// The number of events to cache when paging through history.
        public var historyBufferSize: Int32 = 500

        /// The amount of time (ms) to try checkpoint after.
        public var checkpointAfter: TimeSpan  = .ms(2)

        /// The strategy to use for distributing events to client consumers.
        public var consumerStrategy: SystemConsumerStrategy = .roundRobin

    
    }
}
