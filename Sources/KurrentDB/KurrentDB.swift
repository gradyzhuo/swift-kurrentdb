//
//  KurrentDB.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/27.
//
import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCNIOTransportHTTP2
import NIO
import NIOSSL

/// `KurrentDBClient`
/// A client to encapsulates GRPC usecases to EventStoreDB.
public struct KurrentDBClient: Sendable, Buildable {
    public private(set) var defaultCallOptions: CallOptions
    public private(set) var settings: ClientSettings
    package let group: EventLoopGroup

    ///Construct `KurrentDBClient`  with `ClientSettings` and `numberOfThreads`.
    /// - Parameters:
    ///   - settings: encapsulates various configuration settings for a client.
    ///   - numberOfThreads: the number of threads of `EventLoopGroup` in `NIOChannel`.
    ///   - defaultCallOptions: the default call options for all grpc calls in KurrentDBClient.
    public init(settings: ClientSettings, numberOfThreads: Int = 1, defaultCallOptions: CallOptions = .defaults) {
        self.defaultCallOptions = defaultCallOptions
        self.settings = settings
        group = MultiThreadedEventLoopGroup(numberOfThreads: numberOfThreads)
    }
}

extension KurrentDBClient {
    /// The client instance of `Streams` by identifier, which constructed by settings passed in KurrentDBClient.
    /// - Parameter identifier: the instance of `StreamIdentifier`.
    /// - Returns: the instance of `Streams` to operate.
    public func streams<Target: StreamTarget>(of target: Target)-> Streams<Target>{
        return .init(stream: target, settings: settings, callOptions: defaultCallOptions)
    }
    
    
    ///The client instance of `PersistentSubscriptions`, which constructed by settings passed in KurrentDBClient.
    public func persistentSubscriptions<Target: StreamTarget>(streams target: Target)-> PersistentSubscriptions<Target>{
        return .init(stream: target, settings: settings, callOptions: defaultCallOptions)
    }
    
    ///The client instance of `Projections`, which constructed by settings passed in KurrentDBClient.
    public var projections: Projections {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    ///The client instance of `Users`, which constructed by settings passed in KurrentDBClient.
    public var users: Users {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    ///The client instance of `Monitoring`, which constructed by settings passed in KurrentDBClient.
    public var monitoring: Monitoring {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
    
    ///The client instance of `Operations`, which constructed by settings passed in KurrentDBClient.
    public var operations: Operations {
        .init(settings: settings, callOptions: defaultCallOptions, eventLoopGroup: group)
    }
}


