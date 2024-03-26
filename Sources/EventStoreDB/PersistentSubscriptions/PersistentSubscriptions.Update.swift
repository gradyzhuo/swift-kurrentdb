//
//  PersistentSubscriptions.Update.swift
//
//
//  Created by Grady Zhuo on 2023/12/7.
//

import Foundation
import GRPCSupport

protocol PersistentSubscriptionsUpdateOptions: PersistentSubscriptionsCommonOptions {
    
}


extension PersistentSubscriptionsClient {
    public struct Update {
        public struct Request: GRPCRequest {
            public typealias UnderlyingMessage = EventStore_Client_PersistentSubscriptions_UpdateReq
        }
        
        
    }
}

extension PersistentSubscriptionsClient.Update {
    
    public struct ToStream : UnaryUnary{
        
        public typealias Request = PersistentSubscriptionsClient.Update.Request
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_UpdateResp>
        
        var streamIdentifier: Stream.Identifier
        var groupName: String
        var options: Options
        
        
        public func build() throws -> Request.UnderlyingMessage {
            return try .with{
                $0.options = options.build()
                $0.options.groupName = groupName
                $0.options.stream.streamIdentifier = try streamIdentifier.build()
            }
        }
        
        public class Options: PersistentSubscriptionsUpdateOptions {
            
            public typealias UnderlyingMessage = PersistentSubscriptionsClient.Update.Request.UnderlyingMessage.Options
            
            public var settings: PersistentSubscriptionsClient.Settings = .init()
            public var revisionCursor: Cursor<Stream.Revision> = .end
            
            @discardableResult
            public func startFrom(cursor: Cursor<Stream.Revision>) -> Self{
                self.revisionCursor = cursor
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
    
    public struct ToAll : UnaryUnary{
        public typealias Request = PersistentSubscriptionsClient.Update.Request
        public typealias Response = DiscardedResponse<EventStore_Client_PersistentSubscriptions_UpdateResp>
        
        var groupName: String
        var options: Options
        
        public func build() throws -> Request.UnderlyingMessage {
            return .with{
                $0.options = options.build()
                $0.options.groupName = groupName
            }
        }
        
        public class Options: PersistentSubscriptionsUpdateOptions {
            public typealias UnderlyingMessage = PersistentSubscriptionsClient.Update.Request.UnderlyingMessage.Options
            
            public var settings: PersistentSubscriptionsClient.Settings = .init()
            public var positionCursor: Cursor<Stream.Position> = .end
            
            @discardableResult
            public func startFrom(cursor: Cursor<Stream.Position>) -> Self{
                self.positionCursor = cursor
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

                    
                }
            }
        }
    }
}
