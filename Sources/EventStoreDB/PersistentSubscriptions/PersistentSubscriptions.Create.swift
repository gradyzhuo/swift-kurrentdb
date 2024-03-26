//
//  PersistentSubscriptions.Create.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCSupport

protocol PersistentSubscriptionsCreateOptions: PersistentSubscriptionsCommonOptions {
    
}

extension PersistentSubscriptionsCreateOptions {
    @discardableResult
    public mutating func set(consumerStrategy: PersistentSubscriptionsClient.SystemConsumerStrategy) -> Self {
        settings.consumerStrategy = consumerStrategy
        return self
    }
}

extension PersistentSubscriptionsClient {
    
    public struct Create {
        public struct Request: GRPCRequest {
            public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_CreateReq
        }
        
        
        public struct ToStream: UnaryUnary{
            public typealias Request = Create.Request
            
            public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_CreateResp>
            
            var streamIdentifier: Stream.Identifier
            var groupName: String
            var options: Options
            
            
            public func build() throws -> Create.Request.UnderlyingMessage {
                
                return try .with {
                    $0.options = options.build()
                    $0.options.groupName = groupName
                    $0.options.stream.streamIdentifier = try streamIdentifier.build()
                }
            }
        }
        
        public struct ToAll: UnaryUnary{
            public typealias Request = Create.Request
            
            public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_CreateResp>
            
            
            var groupName: String
            var options: Options
            
            
            public func build() throws -> Create.Request.UnderlyingMessage {
                
                return .with {
                    $0.options = options.build()
                    $0.options.groupName = groupName
                }
            }
        }
    }
    
}



extension PersistentSubscriptionsClient.Create {
    
    public enum SystemConsumerStrategy: RawRepresentable {
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
            return switch self {
            case .dispatchToSingle:
                "dispatchToSingle"
            case .roundRobin:
                "roundRobin"
            case .pinned:
                "pinned"
            case .pinnedByCorrelation:
                "pinnedByCorrelation"
            case .custom(let value):
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


extension PersistentSubscriptionsClient.Create.ToStream {
    public final class Options: PersistentSubscriptionsCreateOptions{
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        public var settings: PersistentSubscriptionsClient.Settings = .init()
        public var revisionCursor: Cursor<Stream.Revision> = .end
        
        @discardableResult
        public func startFrom(revision: Cursor<Stream.Revision>) -> Self{
            self.revisionCursor = revision
            return self
        }
        
        public func build() -> UnderlyingMessage {
            return .with{
                $0.settings = .make(settings: settings)
                
                switch revisionCursor {
                case .start:
                    $0.stream.start = .init()
                case .end:
                    $0.stream.end = .init()
                case .specified(let revision):
                    $0.stream.revision = revision.value
                }
            }
        }
        
        
    }
}

extension PersistentSubscriptionsClient.Create.ToAll{
    public final class Options: PersistentSubscriptionsCreateOptions{
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        public var settings: PersistentSubscriptionsClient.Settings = .init()
        public var filter: StreamClient.FilterOption? = nil
        public var positionCursor: Cursor<Stream.Position> = .end
        
        @discardableResult
        public func startFrom(position: Cursor<Stream.Position>) -> Self{
            self.positionCursor = position
            return self
        }
        
        public func build() -> UnderlyingMessage {
            
            return .with {
                $0.settings = .make(settings: settings)
                switch positionCursor {
                case .start:
                    $0.all.start = .init()
                case .end:
                    $0.all.end = .init()
                case .specified(let pointer):
                    $0.all.position = .with{
                        $0.commitPosition = pointer.commit
                        $0.preparePosition = pointer.prepare
                    }
                }
                
                if let filter {
                    $0.all.filter = .make(with: filter)
                }else{
                    $0.all.noFilter = .init()
                }
                
            }
        }
        
    }
    
}

