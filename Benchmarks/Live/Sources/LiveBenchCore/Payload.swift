import Foundation

/// Builds deterministic JSON payloads of an exact byte size: `{"i":<index>,"p":"<filler>"}`.
///
/// The seeded filler is generated once, at init, as a pool of `poolSize` bodies per payload kind (data, metadata), so
/// building an event on the operation path is two small copies, not one splitmix64 step per byte. Index `k` uses
/// pool entry `k % poolSize`, truncated to the filler length its decimal index leaves. The exact rule, which every
/// driver reproduces byte for byte, is in `docs/driver-contract.md` ("Event bytes").
public struct PayloadFactory: Sendable {
    public static let poolSize = 1024

    public let dataSize: Int
    public let metadataSize: Int
    public let seed: UInt64

    private let dataPool: FillerPool
    private let metadataPool: FillerPool

    public init(dataSize: Int, metadataSize: Int, seed: UInt64) {
        self.dataSize = dataSize
        self.metadataSize = metadataSize
        self.seed = seed
        dataPool = FillerPool(size: dataSize, seed: seed)
        metadataPool = FillerPool(size: metadataSize, seed: seed &+ 0x9E37_79B9_7F4A_7C15)
    }

    public func data(index: Int) -> Data { dataPool.payload(index: index) }

    public func metadata(index: Int) -> Data { metadataPool.payload(index: index) }
}

/// `poolSize` filler bodies of the longest filler a payload of `size` bytes can hold (that of a one-digit index).
private struct FillerPool: Sendable {
    private static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
    private static let suffix = Array("\"}".utf8)

    let size: Int
    /// Entry j occupies `bytes[j * width ..< (j + 1) * width]`.
    private let bytes: [UInt8]
    private let width: Int

    init(size: Int, seed: UInt64) {
        let width = size - Self.prefix(index: 0).count - Self.suffix.count
        precondition(width >= 0, "payload size \(size) is too small")
        var bytes = [UInt8]()
        bytes.reserveCapacity(width * PayloadFactory.poolSize)
        for j in 0..<PayloadFactory.poolSize {
            // splitmix64 seeded per entry: state = seed XOR (j * 0xBF58476D1CE4E5B9)
            var state = seed ^ (UInt64(j) &* 0xBF58_476D_1CE4_E5B9)
            for _ in 0..<width {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                z ^= z >> 31
                bytes.append(Self.alphabet[Int(z % UInt64(Self.alphabet.count))])
            }
        }
        self.size = size
        self.bytes = bytes
        self.width = width
    }

    static func prefix(index: Int) -> [UInt8] { Array("{\"i\":\(index),\"p\":\"".utf8) }

    func payload(index: Int) -> Data {
        let prefix = Self.prefix(index: index)
        let fillerCount = size - prefix.count - Self.suffix.count
        precondition(fillerCount >= 0, "payload size \(size) is too small for index \(index)")
        let entry = (index % PayloadFactory.poolSize + PayloadFactory.poolSize) % PayloadFactory.poolSize
        var data = Data(capacity: size)
        data.append(contentsOf: prefix)
        data.append(contentsOf: bytes[entry * width ..< entry * width + fillerCount])
        data.append(contentsOf: Self.suffix)
        return data
    }
}
