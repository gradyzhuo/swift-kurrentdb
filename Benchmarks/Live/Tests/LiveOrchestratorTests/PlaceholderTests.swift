@testable import LiveBenchCore
import Testing

@Suite("Orchestrator placeholder")
struct PlaceholderTests {
    @Test func fixturesAreShared() { _ = EffectiveScenario.fixture() }
}
