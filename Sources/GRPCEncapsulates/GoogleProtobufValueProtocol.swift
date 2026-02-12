//
//  GoogleProtobufValueProtocol.swift
//  KurrentDB-Swift
//
//  Created by Grady Zhuo on 2026/2/12.
//
import SwiftProtobuf

package protocol GoogleProtobufValueProtocol {
    var protobufValue: Google_Protobuf_Value { get }
}

extension Bool: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(boolValue: self)
        }
    }
}

extension Int: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension Int8: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension Int16: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension Int32: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension Int64: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension Int128: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension UInt: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}


extension UInt8: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}


extension UInt16: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension UInt32: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension UInt64: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}

extension UInt128: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}



extension Double: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: self)
        }
    }
}

extension Float: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}


extension Float16: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(numberValue: Double(self))
        }
    }
}



extension String: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(stringValue: self)
        }
    }
}

extension Optional: GoogleProtobufValueProtocol where Wrapped: GoogleProtobufValueProtocol {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return switch self {
            case .none:
                .init(nilLiteral: ())
            case .some(let value):
                value.protobufValue
            }
        }
    }
}

extension Array: GoogleProtobufValueProtocol where Element: Any {
    package var protobufValue: Google_Protobuf_Value {
        get {
            let values = self.map{
                return switch $0{
                case let stringValue as String:
                    stringValue.protobufValue
                case let doubleValue as Double:
                    doubleValue.protobufValue
                case let intValue as Int:
                    intValue.protobufValue
                case let floatValue as Float:
                    floatValue.protobufValue
                case let boolValue as Bool:
                    boolValue.protobufValue
                case let dictionaryValue as [String: Any]:
                    dictionaryValue.protobufValue
                case let arrayValue as [Any]:
                    arrayValue.protobufValue
                default:
                    Google_Protobuf_Value.init(nilLiteral: ())
                }
            }
            return .init(listValue: .init(values: values))
        }
    }
}

extension Dictionary: GoogleProtobufValueProtocol where Key == String, Value: Any {
    package var protobufValue: Google_Protobuf_Value {
        get {
            return .init(structValue: structValue)
        }
    }
    
    package var structValue: Google_Protobuf_Struct {
        get {
            let items = self.map{
                let value = switch $0.value{
                case let stringValue as String:
                    stringValue.protobufValue
                case let doubleValue as Double:
                    doubleValue.protobufValue
                case let intValue as Int:
                    intValue.protobufValue
                case let floatValue as Float:
                    floatValue.protobufValue
                case let boolValue as Bool:
                    boolValue.protobufValue
                case let arrayValue as [Any]:
                    arrayValue.protobufValue
                case let dictionaryValue as [String: Any]:
                    dictionaryValue.protobufValue
                default:
                    Google_Protobuf_Value.init(nilLiteral: ())
                }
                return ($0.key, value)
            }
            let fields = [Key: Google_Protobuf_Value].init(uniqueKeysWithValues: items)
            return .init(fields: fields)
        }
    }
    
    
}


