import Testing
@testable import Tooling

@Suite struct ReleaseVersionTests {
    @Test func parsesPlainReleaseNumbersOnly() {
        #expect(ReleaseVersion("2.7.0") == ReleaseVersion(major: 2, minor: 7, patch: 0))
        #expect(ReleaseVersion("2.7.0")?.series == "2.7")
        for text in ["v2.7.0", "2.7", "2.0.0-beta.5", "pre/2.7.0", "2..0", "２.7.0"] {
            #expect(ReleaseVersion(text) == nil, Comment(rawValue: text))
        }
    }

    @Test func ordersNumerically() {
        #expect(ReleaseVersion("2.10.0")! > ReleaseVersion("2.9.3")!)
        #expect(ReleaseVersion("2.7.1")! > ReleaseVersion("2.7.0")!)
    }
}
