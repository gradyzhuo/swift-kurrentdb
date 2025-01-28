//
//  Deprecated.swift
//  EventStoreDB
//
//  Created by 卓俊諺 on 2025/1/27.
//

import KurrentDB

public enum Stream {
    @available(*, deprecated, message: "please use StreamIdentifier from KurrentCore instead.")
    public typealias Identifier = StreamIdentifier

    @available(*, deprecated, message: "please use StreamMetadata from KurrentCore instead.")
    public typealias Metadata = StreamMetadata

    @available(*, deprecated, message: "please use StreamPosition from KurrentCore instead.")
    public typealias Position = StreamPosition

    @available(*, deprecated, message: "please use StreamRevision from KurrentCore instead.")
    public typealias Revision = StreamRevision

    @available(*, deprecated, message: "please use StreamSelector from KurrentCore instead.")
    public typealias Selector = StreamSelector
}
