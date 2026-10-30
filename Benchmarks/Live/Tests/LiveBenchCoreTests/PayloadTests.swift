import Foundation
import Testing
@testable import LiveBenchCore

@Suite("Payload")
struct PayloadTests {
    @Test(arguments: [300, 1024, 4096])
    func payloadHasExactSizeAndIsJSON(size: Int) throws {
        let f = PayloadFactory(dataSize: size, metadataSize: 60, seed: 42)
        #expect(f.data(index: 7).count == size)
        #expect(f.metadata(index: 7).count == 60)
        _ = try JSONSerialization.jsonObject(with: f.data(index: 7))
        _ = try JSONSerialization.jsonObject(with: f.metadata(index: 7))
    }

    @Test func payloadIsDeterministic() {
        #expect(PayloadFactory(dataSize: 300, metadataSize: 60, seed: 1).data(index: 3)
            == PayloadFactory(dataSize: 300, metadataSize: 60, seed: 1).data(index: 3))
    }

    @Test(arguments: [0, 9, 10, 1023, 1024, 99_999, 1_000_000_007])
    func everyIndexHasExactSizes(index: Int) throws {
        let f = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 42)
        #expect(f.data(index: index).count == 300)
        #expect(f.metadata(index: index).count == 60)
        let object = try #require(try JSONSerialization.jsonObject(with: f.data(index: index)) as? [String: Any])
        #expect(object["i"] as? Int == index)
    }

    /// Fillers come from a pool of 1024 seeded bodies: indices 1024 apart share the body but differ in "i".
    @Test func indicesAPoolApartShareFillerButNotIndex() {
        let f = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 42)
        let a = f.data(index: 5), b = f.data(index: 5 + 1024)
        #expect(a != b)
        // Same digit count, so the same filler length: everything after the index is identical.
        func afterIndex(_ d: Data) -> Data { d[d.firstIndex(of: UInt8(ascii: ","))!...] }
        let c = f.data(index: 1029), d = f.data(index: 1029 + 1024)
        #expect(afterIndex(c) == afterIndex(d))
        #expect(c != d)
    }

    /// Pool entry j is the contract's filler generator for index j, so an index below 1024 with the longest filler
    /// (one digit) matches the generator exactly; longer indices use a prefix of their entry.
    @Test func poolEntryIsTheSeededGenerator() {
        let f = PayloadFactory(dataSize: 40, metadataSize: 20, seed: 9)
        func reference(size: Int, k: Int, seed: UInt64) -> Data {
            let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".utf8)
            let prefix = Array("{\"i\":\(k),\"p\":\"".utf8)
            let poolEntry = k % 1024
            let maxFiller = size - Array("{\"i\":0,\"p\":\"".utf8).count - 2
            var state = seed ^ (UInt64(poolEntry) &* 0xBF58_476D_1CE4_E5B9)
            var filler: [UInt8] = []
            for _ in 0..<maxFiller {
                state &+= 0x9E37_79B9_7F4A_7C15
                var z = state
                z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
                z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
                z ^= z >> 31
                filler.append(alphabet[Int(z % 62)])
            }
            return Data(prefix + Array(filler.prefix(size - prefix.count - 2)) + Array("\"}".utf8))
        }
        for k in [0, 7, 42, 1023, 1024, 5000, 123_456] {
            #expect(f.data(index: k) == reference(size: 40, k: k, seed: 9))
            #expect(f.metadata(index: k) == reference(size: 20, k: k, seed: 9 &+ 0x9E37_79B9_7F4A_7C15))
        }
    }

    @Test func payloadVariesWithIndexAndSeed() {
        let a = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 1)
        let b = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 2)
        #expect(a.data(index: 1) != a.data(index: 2))
        #expect(a.data(index: 1) != b.data(index: 1))
    }
}
