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

    @Test func payloadVariesWithIndexAndSeed() {
        let a = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 1)
        let b = PayloadFactory(dataSize: 300, metadataSize: 60, seed: 2)
        #expect(a.data(index: 1) != a.data(index: 2))
        #expect(a.data(index: 1) != b.data(index: 1))
    }
}
