/// The seeded random choices of the driver contract ("Random choices" in `docs/driver-contract.md`): splitmix64
/// seeded with the scenario's `seed`, one draw per operation index, in index order.
///
/// Draw *i* only depends on `seed` and *i* (the generator's state after *i + 1* steps is `seed + (i + 1) * gamma`), so
/// any operation can compute its own draw without shared state, and every client draws the same sequence.
public enum SeededDraw {
    private static let gamma: UInt64 = 0x9E37_79B9_7F4A_7C15

    /// The `index`-th (0-based) output of splitmix64 seeded with `seed`.
    public static func draw(seed: UInt64, index: Int) -> UInt64 {
        var z = seed &+ (UInt64(truncatingIfNeeded: index) &+ 1) &* gamma
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    /// `draw(seed:index:) % count`: the stream (or rebuild stream) operation `index` uses.
    public static func pick(seed: UInt64, index: Int, count: Int) -> Int {
        precondition(count > 0, "count must be positive")
        return Int(draw(seed: seed, index: index) % UInt64(count))
    }
}
