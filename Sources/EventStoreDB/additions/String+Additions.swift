//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2024/1/1.
//

import Foundation


extension String {
    
    public func parse() throws -> ClientSettings {
        return try ClientSettings.parse(connectionString:self)
    }
    
    
}
