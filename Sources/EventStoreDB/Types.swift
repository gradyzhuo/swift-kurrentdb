//
//  File.swift
//  
//
//  Created by 卓俊諺 on 2023/11/9.
//

import Foundation

public struct Duration {
    var secs: UInt64
    var nanos: UInt32 // Always 0 <= nanos < NANOS_PER_SEC
}
