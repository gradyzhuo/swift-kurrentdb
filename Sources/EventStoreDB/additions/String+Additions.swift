//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/1/1.
//

import Foundation

@available(macOS 13.0, *)
extension String {
    
    public func parse<T>() throws -> T where T == ClientSettings{
        return try ClientSettings.parse(connectionString:self)
    }
    
    
}
