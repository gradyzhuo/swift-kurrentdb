@testable import LiveBenchCore
import Testing

@Suite("Seeded draws")
struct SeededDrawTests {
    /// The reference splitmix64 sequence for seed 0 (Vigna's published test vector).
    @Test func matchesReferenceSplitMix64() {
        #expect(SeededDraw.draw(seed: 0, index: 0) == 0xE220_A839_7B1D_CDAF)
        #expect(SeededDraw.draw(seed: 0, index: 1) == 0x6E78_9E6A_A1B9_65F4)
        #expect(SeededDraw.draw(seed: 0, index: 2) == 0x06C4_5D18_8009_454F)
    }

    /// Draw *i* is the *i*-th output of one generator advanced in index order, as the driver contract says.
    @Test func drawIsTheIndexthOutputOfOneGenerator() {
        var state: UInt64 = 42
        for i in 0..<1000 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            z ^= z >> 31
            #expect(SeededDraw.draw(seed: 42, index: i) == z)
        }
    }

    @Test func pickIsDrawModuloCount() {
        for i in 0..<100 {
            #expect(SeededDraw.pick(seed: 7, index: i, count: 100_000) == Int(SeededDraw.draw(seed: 7, index: i) % 100_000))
        }
    }
}
