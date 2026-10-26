import Foundation

/// Builds deterministic JSON payloads of an exact byte size: `{"i":<index>,"p":"<filler>"}`
/// padded with seeded ASCII filler.
public struct PayloadFactory: Sendable {
    public let dataSize: Int
    public let metadataSize: Int
    public let seed: UInt64

    public init(dataSize: Int, metadataSize: Int, seed: UInt64) {
        self.dataSize = dataSize
        self.metadataSize = metadataSize
        self.seed = seed
    }

    public func data(index: Int) -> Data { Self.make(size: dataSize, index: index, seed: seed) }

    public func metadata(index: Int) -> Data { Self.make(size: metadataSize, index: index, seed: seed &+ 0x9E37_79B9_7F4A_7C15) }

    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)

    private static func make(size: Int, index: Int, seed: UInt64) -> Data {
        let prefix = Array("{\"i\":\(index),\"p\":\"".utf8)
        let suffix = Array("\"}".utf8)
        let fillerCount = size - prefix.count - suffix.count
        precondition(fillerCount >= 0, "payload size \(size) is too small for index \(index)")
        var state = seed ^ (UInt64(truncatingIfNeeded: index) &* 0xBF58_476D_1CE4_E5B9)
        var bytes = prefix
        bytes.reserveCapacity(size)
        for _ in 0..<fillerCount {
            // splitmix64
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            bytes.append(alphabet[Int(z % UInt64(alphabet.count))])
        }
        bytes.append(contentsOf: suffix)
        return Data(bytes)
    }
}
