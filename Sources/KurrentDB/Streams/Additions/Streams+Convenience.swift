//
//  Streams+Convenience.swift
//  KurrentDB
//
//  Created by Grady Zhuo on 2025/3/9.
//

extension Streams where Target == SpecifiedStream {
    
    /// Appends a list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events: The list of events to append.
    ///   - configure: configure closure for  `Append` options .
    /// - Returns: An `Append.Response` indicating the result of the operation.
    public func append(events: [EventData], configure: (Append.Options) throws ->Append.Options) async throws -> Append.Response {
        let options = try configure(.init())
        return try await append(events: events, options: options)
    }
    
    /// Appends a list of events to the specified stream.
    ///
    /// - Parameters:
    ///   - events: The list of events to append by variadic parameters form.
    ///   - configure: Options for appending events.
    /// - Returns: An `Append.Response` indicating the result of the operation.
    public func append(events: EventData..., configure: (Append.Options)->Append.Options) async throws -> Append.Response {
        let options = configure(.init())
        return try await append(events: events, options: options)
    }
    
    /// Reads events from the specified stream.
    /// - Parameters:
    ///   - cursor: The position in the stream from which to read.
    ///   - configure: configure closure for `Read` options.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    public func read(cursor: Cursor<CursorPointer>, configure: (Read.Options) throws ->Read.Options) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let options = try configure(.init())
        return try await read(cursor: cursor, options: options)
    }
    
    /// Reads events from the specified stream.
    /// - Parameters:
    ///   - revision: The revision of the stream that will be read from it.
    ///   - direction: The direction to read.
    ///   - configure: configure closure for `Read` options.
    /// - Returns: An asynchronous stream of `Read.Response` values.
    public func read(from revision: UInt64, directTo direction: Direction, configure: (Read.Options) throws ->Read.Options) async throws -> AsyncThrowingStream<Read.Response, Error> {
        let options = try configure(.init())
        return try await read(cursor: .specified(.init(revision: revision, direction: direction)), options: options)
    }

    /// Subscribes to events from the specified stream.
    /// - Parameters:
    ///   - cursor: The position in the stream from which to subscribe.
    ///   - configure: configure closure for `Subscription` options.
    /// - Returns: An asynchronous stream of `Subscribe.Response` values.
    public func subscribe(cursor: Cursor<StreamRevision>, configure: (Subscribe.Options) throws ->Subscribe.Options) async throws -> Subscription {
        let options = try configure(.init())
        return try await subscribe(cursor: cursor, options: options)
    }

    /// Deletes the specified stream.
    ///
    /// - Parameter configure: configure closure for `Delete` options.
    /// - Returns: A `Delete.Response` indicating the result of the operation.
    @discardableResult
    public func delete(configure: (Delete.Options) throws -> Delete.Options) async throws -> Delete.Response {
        let options = try configure(.init())
        return try await delete(options: options)
    }
    
    /// Marks the specified stream as permanently deleted (tombstoned).
    /// - Parameter configure: configure closure for `Tombstone` options.
    /// - Returns: A `Tombstone.Response` indicating the result of the operation.
    @discardableResult
    public func tombstone(configure: (Tombstone.Options) throws -> Tombstone.Options) async throws -> Tombstone.Response {
        let options = try configure(.init())
        return try await tombstone(options: options)
    }
}

extension Streams where Target == AllStreams {
    /// Reads events from all available streams.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to read.
    ///   - configure: configure closure for `ReadAll` options.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    public func read(cursor: Cursor<ReadAll.CursorPointer>, configure: (ReadAll.Options) throws ->ReadAll.Options) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let options = try configure(.init())
        return try await read(cursor: cursor, options: options)
    }

    /// Reads events from a specified position and direction in all streams.
    ///
    /// - Parameters:
    ///   - position: The starting position in the stream.
    ///   - direction: The reading direction.
    ///   - configure: configure closure for `ReadAll` options.
    /// - Returns: An asynchronous stream of `ReadAll.Response` values.
    public func read(from position: StreamPosition, directTo direction: Direction, configure: (ReadAll.Options) throws ->ReadAll.Options) async throws -> AsyncThrowingStream<ReadAll.Response, Error> {
        let options = try configure(.init())
        return try await read(cursor: .specified(.init(position: position, direction: direction)), options: options)
    }

    /// Subscribes to all streams from a specified position.
    ///
    /// - Parameters:
    ///   - cursor: The position from which to subscribe.
    ///   - configure: configure closure for `SubscribeAll` options.
    /// - Returns: A `Streams.Subscription` instance.
    public func subscribe(cursor: Cursor<StreamPosition>, configure: (SubscribeAll.Options) throws ->SubscribeAll.Options) async throws -> Streams.Subscription {
        let options = try configure(.init())
        return try await subscribe(cursor: cursor, options: options)
    }
    
    /// Subscribes to all streams from a specified position.
    ///
    /// - Parameters:
    ///   - position: The starting position in the stream.
    ///   - configure: configure closure for `SubscribeAll` options.
    /// - Returns: A `Streams.Subscription` instance.
    public func subscribe(from position: StreamPosition, configure: (SubscribeAll.Options) throws ->SubscribeAll.Options) async throws -> Streams.Subscription {
        let options = try configure(.init())
        return try await subscribe(cursor: .specified(position), options: options)
    }
}
