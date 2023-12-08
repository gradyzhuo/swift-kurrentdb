//
//  File.swift
//  
//
//  Created by Ospark.org on 2023/11/9.
//

import Foundation
import SwiftProtobuf
//
//func parse<T:Codable>(protobufValue value: Google_Protobuf_Value)->T?{
//    guard let kind = value.kind else {
//        return nil
//    }
//    switch kind {
//    case let .boolValue(value):
//        return value as? T
//    case let .nullValue(value):
//        return value as? T
//    case let .numberValue(value):
//        if T.self is (any Numeric) {
//            return parseNumericValue(value)
//        }
//        
//    case let .stringValue(value):
//        return value as? T
//    case let .structValue(value):
//        for field in value.fields{
//            parse(protobufValue: <#T##Google_Protobuf_Value#>)
//        }
//        
////        let results:[(String, Codable)] = value.fields.reduce(.init()) {
////            $0 + (key: $1.key, )
////        }
////        value.fields.map{
////            (key: key, )
////        }
//        return nil
//    case let .listValue(value):
//        return nil
//    }
//}
//
//func parseNumericValue<T>(_ value: Double)->T? where T: Codable, T: Numeric {
//    guard let kind = value.kind else {
//        return nil
//    }
//    
//    switch kind {
//    case let .numberValue(value):
//        return Int(value) as? T
//    default:
//        return nil
//    }
//    
//}
