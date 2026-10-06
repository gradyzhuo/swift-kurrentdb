//
//  ReadOverloadResolutionTests.swift
//  swift-kurrentdb
//
//  Compile-level pins for the two `read(configure:)` overloads (spec §6). The closures below are
//  never executed; they exist so the compiler proves which overload each call shape resolves to.
//  If the ReadCall overload ever becomes `async`/`throws`, or ReadCall conforms to AsyncSequence,
//  these stop compiling — that is the point.
//

import Testing
@testable import KurrentDB

@Suite("read overload resolution")
struct ReadOverloadResolutionTests {
    private func acceptsOldStream(_: AsyncThrowingStream<Streams<SpecifiedStream>.ReadResponse, any Error>) {}
    private func acceptsOldAllStream(_: AsyncThrowingStream<Streams<AllStreamsTarget>.ReadResponse, any Error>) {}
    private func acceptsLazy(_: Streams<SpecifiedStream>.ReadCall.Lazy) {}
    private func acceptsSpecifiedCall(_: Streams<SpecifiedStream>.ReadCall) {}
    private func acceptsCall(_: Streams<AllStreamsTarget>.ReadCall) {}

    @Test("Existing call shapes resolve to the buffered overload; member chains resolve to ReadCall")
    func shapes() {
        let client = MockKurrentDBClient()
        let specified = client.streams(specified: "orders")
        let all = client.allStreams

        // Existing shapes (never run; type-checked only).
        let _: () async throws -> Void = {
            acceptsOldStream(try await specified.read())
            acceptsOldStream(try await specified.read { $0.limit = 10 })
            acceptsOldAllStream(try await all.read())
            for try await _ in try await specified.read() {}
            let responses = try await all.read()
            for try await _ in responses {}
            _ = try await specified.read().reduce(0) { count, _ in count + 1 }
        }

        // Unannotated function references keep binding to the buffered overload (async context).
        let _: () async throws -> Void = {
            let readRef = specified.read
            let allReadRef = all.read
            acceptsOldStream(try await readRef({ _ in }))
            acceptsOldStream(try await readRef({ $0.limit = 10 }))
            acceptsOldAllStream(try await allReadRef({ _ in }))
            acceptsOldAllStream(try await allReadRef({ $0.limit = 10 }))
        }
        let _: () async throws -> Void = { acceptsOldStream(try await specified.read()) }

        // Known limitation: a reference formed in a synchronous context binds to the ReadCall overload.
        let syncRef = specified.read
        acceptsSpecifiedCall(syncRef({ _ in }))

        // New shapes.
        acceptsLazy(specified.read().lazy)
        acceptsLazy(specified.read { $0.limit = 10 }.lazy)
        acceptsCall(all.read())
        let call: Streams<SpecifiedStream>.ReadCall = specified.read()
        _ = call
        let _: () async throws -> Void = {
            for try await _ in specified.read().lazy {}
            for try await _ in try await all.read().buffered {}
            _ = try await specified.read().lazy.first { _ in true }
        }
        #expect(Bool(true))
    }
}
