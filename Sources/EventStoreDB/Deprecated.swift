//
//  Deprecated.swift
//  KurrentDB
//
//  Created by 卓俊諺 on 2025/1/27.
//

import KurrentDB

public struct Stream {
    @available(*, deprecated, message: "please use StreamIdentifier instead.")
    public typealias Identifier = StreamIdentifier
    
    @available(*, deprecated, message: "please use StreamMetadata instead.")
    public typealias Metadata = StreamMetadata
    
    @available(*, deprecated, message: "please use StreamPosition instead.")
    public typealias Position = StreamPosition
    
    @available(*, deprecated, message: "please use StreamRevision instead.")
    public typealias Revision = StreamRevision
    
    @available(*, deprecated, message: "please use StreamSelector instead.")
    public typealias Selector = StreamSelector
}
