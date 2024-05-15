//
//  PersistentSubscriptions.Create.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCEncapsulates

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
            
            
            package func build() throws -> Create.Request.UnderlyingMessage {
                
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
            
            
            package func build() throws -> Create.Request.UnderlyingMessage {
                
                return .with {
                    $0.options = options.build()
                    $0.options.groupName = groupName
                }
            }
        }
    }
    
}



extension PersistentSubscriptionsClient.Create.ToStream {
    public final class Options: PersistentSubscriptionsCreateOptions{
        public typealias UnderlyingMessage = Request.UnderlyingMessage.Options
        
        public var settings: PersistentSubscriptionsClient.Settings
        public var revisionCursor: Cursor<Stream.Revision>
        
        public init(settings: PersistentSubscriptionsClient.Settings = .init(), revisionCursor: Cursor<Stream.Revision> = .end) {
            self.settings = settings
            self.revisionCursor = revisionCursor
        }
        
        @discardableResult
        public func startFrom(revision: Cursor<Stream.Revision>) -> Self{
            self.revisionCursor = revision
            return self
        }
        
        package func build() -> UnderlyingMessage {
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
        
        public var settings: PersistentSubscriptionsClient.Settings
        public var filter: StreamClient.FilterOption?
        public var positionCursor: Cursor<Stream.Position>
        
        public init(settings: PersistentSubscriptionsClient.Settings = .init(), filter: StreamClient.FilterOption? = nil, positionCursor: Cursor<Stream.Position> = .end) {
            self.settings = settings
            self.filter = filter
            self.positionCursor = positionCursor
        }
        
        @discardableResult
        public func startFrom(position: Cursor<Stream.Position>) -> Self{
            self.positionCursor = position
            return self
        }
        
        package func build() -> UnderlyingMessage {
            
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

