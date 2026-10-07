//
//  DefaultDeadlineTests.swift
//  KurrentCoreTests
//

import GRPCCore
@testable import KurrentDB
import Testing

@Suite("ClientSettings.defaultDeadline → CallOptions.timeout")
struct DefaultDeadlineTests {
    @Test("A default deadline becomes the call timeout when the options carry none")
    func appliesWhenUnset() {
        let settings = ClientSettings.localhost().defaultDeadline(5000)
        let options = CallOptions.defaults.applyingDefaultDeadline(from: settings)
        #expect(options.timeout == .milliseconds(5000))
    }

    @Test("A timeout set on the options wins over the default deadline")
    func explicitTimeoutWins() {
        let settings = ClientSettings.localhost().defaultDeadline(5000)
        var explicit = CallOptions.defaults
        explicit.timeout = .seconds(1)
        #expect(explicit.applyingDefaultDeadline(from: settings).timeout == .seconds(1))
    }

    @Test(".max and non-positive deadlines leave the options without a timeout")
    func noDeadline() {
        #expect(CallOptions.defaults.applyingDefaultDeadline(from: .localhost()).timeout == nil)
        #expect(CallOptions.defaults.applyingDefaultDeadline(from: .localhost().defaultDeadline(0)).timeout == nil)
        #expect(CallOptions.defaults.applyingDefaultDeadline(from: .localhost().defaultDeadline(-1)).timeout == nil)
    }

    @Test("The connection string's defaultDeadline reaches the call timeout")
    func fromConnectionString() throws {
        let settings = try ClientSettings.parse(connectionString: "esdb://localhost:2113?tls=false&defaultDeadline=2500")
        #expect(settings.defaultDeadline == 2500)
        #expect(CallOptions.defaults.applyingDefaultDeadline(from: settings).timeout == .milliseconds(2500))
    }
}
