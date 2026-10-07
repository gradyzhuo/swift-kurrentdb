//
//  WireIntegers.swift
//  KurrentCore
//

/// Converts a signed protobuf field that the SDK models as unsigned (revisions, log positions).
///
/// The v2 protocol declares these as `sint64`. `UInt64(_:)` traps on a negative value, which a
/// faulty server or anything able to alter the response could send, so the conversion must fail
/// as a decoding error instead of terminating the process.
package func unsignedWireValue(_ value: Int64, field: String) throws(KurrentError) -> UInt64 {
    guard let unsigned = UInt64(exactly: value) else {
        throw .internalParsingError(reason: "The server returned a negative \(field) (\(value)).")
    }
    return unsigned
}
