import Benchmark
import Foundation
import GRPCCore
import GRPCEncapsulates
import KurrentDB

// Client-stack benchmarks: a real `KurrentDBClient` (node selection, the retry wrapper, the
// shared connection, the generated client and the response sequences) against an in-process
// server, `FakeKurrentDB`. What the codec benchmarks do not cover is what the client adds on top
// of encoding and decoding. Not covered here: HTTP/2 framing, sockets and the server's own work.
//
// The `GRPC/*` benchmarks make the same calls with the generated gRPC client alone, on the same
// kind of in-process connection behind the same `AnyClientTransport`: `Client/*` minus `GRPC/*` is
// what the SDK adds above that transport, whose own forwarding both include.

private typealias StreamsService = EventStore_Client_Streams_Streams

private let payload = Data(repeating: 0x61, count: 100)

func clientBenchmarks() {
    for count in [1, 100] {
        Benchmark("Client/append/\(count)x100B") { (benchmark, fixture: StreamFixture) in
            for _ in benchmark.scaledIterations {
                blackHole(try await fixture.stream.append(events: fixture.events))
            }
        } setup: {
            try await .appending(count)
        }
    }

    // With a deadline, grpc-swift runs each call it bounds in a task group next to a timer task.
    // The in-process connection keeps the deadline from the server, so only the client's timer runs.
    Benchmark("Client/append-with-deadline/1x100B") { (benchmark, fixture: StreamFixture) in
        for _ in benchmark.scaledIterations {
            blackHole(try await fixture.stream.append(events: fixture.events))
        }
    } setup: {
        try await .appending(1) { $0.defaultDeadline(10000) }
    }

    for count in [1, 100, 1000] {
        Benchmark("Client/read-buffered/\(count)x100B") { (benchmark, fixture: StreamFixture) in
            for _ in benchmark.scaledIterations {
                for try await response in try await fixture.stream.read().buffered {
                    blackHole(response)
                }
            }
        } setup: {
            try await .reading(count)
        }

        Benchmark("Client/read-lazy/\(count)x100B") { (benchmark, fixture: StreamFixture) in
            for _ in benchmark.scaledIterations {
                for try await response in fixture.stream.read().lazy {
                    blackHole(response)
                }
            }
        } setup: {
            try await .reading(count)
        }
    }

    for count in [1, 100] {
        Benchmark("GRPC/append/\(count)x100B") { (benchmark, fixture: GRPCFixture) in
            for _ in benchmark.scaledIterations {
                blackHole(try await fixture.append())
            }
        } setup: {
            try await .appending(count)
        }
    }

    for count in [1, 100, 1000] {
        Benchmark("GRPC/read/\(count)x100B") { (benchmark, fixture: GRPCFixture) in
            for _ in benchmark.scaledIterations {
                blackHole(try await fixture.read())
            }
        } setup: {
            try await .reading(count)
        }
    }
}

/// A warm client on one stream of an in-process server. Setup makes a call first and checks its
/// result (for a read, one buffered and one lazy), so discovery and the shared connection are done
/// before measuring, and a broken in-process path fails the benchmark instead of measuring an
/// error. The node stays cached for longer than a benchmark runs: every measured call takes the
/// path of a long-lived client.
///
/// Each benchmark runs in its own process, so the client is not shut down afterwards.
private struct StreamFixture {
    let stream: Streams<SpecifiedStream>
    let events: [EventData]
    // Held so the client lives as long as the stream it hands out.
    private let client: KurrentDBClient

    private init(
        readResponses: [[UInt8]] = [],
        events: [EventData] = [],
        configure: (ClientSettings) -> ClientSettings = { $0 }
    ) throws {
        var settings = configure(ClientSettings.localhost().nodeCacheTTL(.seconds(3600)))
        settings.transportProvider = try InProcessTransportProvider(
            server: FakeKurrentDB(
                endpoint: settings.endpoints[0],
                appendMessages: events.count + 1,
                readResponses: readResponses
            )
        )
        client = KurrentDBClient(settings: settings)
        stream = client.streams(specified: "orders-abc-123")
        self.events = events
    }

    /// Appends `count` events of 100 bytes per call.
    static func appending(_ count: Int, configure: (ClientSettings) -> ClientSettings = { $0 }) async throws -> Self {
        let events = (0 ..< count).map { _ in EventData(eventType: "OrderPlaced", data: payload) }
        let fixture = try Self(events: events, configure: configure)
        let response = try await fixture.stream.append(events: events)
        guard response.currentRevision == 0 else {
            throw FixtureError("the warm-up append returned \(response)")
        }
        return fixture
    }

    /// Reads a stream of `count` events of 100 bytes per call.
    static func reading(_ count: Int) async throws -> Self {
        let fixture = try Self(readResponses: serializedReadResponses(count: count, payload: payload))
        var buffered: [UInt64] = []
        for try await response in try await fixture.stream.read().buffered {
            try buffered.append(response.event.record.revision)
        }
        var lazy: [UInt64] = []
        for try await response in fixture.stream.read().lazy {
            try lazy.append(response.event.record.revision)
        }
        let expected = Array(0 ..< UInt64(count))
        guard buffered == expected, lazy == expected else {
            throw FixtureError("the warm-up reads returned revisions \(buffered) (buffered) and \(lazy) (lazy)")
        }
        return fixture
    }
}

/// The generated gRPC client alone, on an in-process connection like the ones `StreamFixture`'s
/// client opens and behind the same `AnyClientTransport`: no node selection, no retry and no SDK
/// types around the messages. Setup makes one call first and checks its result, as
/// `StreamFixture` does.
private struct GRPCFixture {
    private let streams: StreamsService.Client<AnyClientTransport>
    private let appendRequest: [EventStore_Client_Streams_AppendReq]
    private let readRequest: EventStore_Client_Streams_ReadReq

    private init(
        readResponses: [[UInt8]] = [],
        appendRequest: [EventStore_Client_Streams_AppendReq] = [],
        readRequest: EventStore_Client_Streams_ReadReq = .init()
    ) throws {
        let endpoint = ClientSettings.localhost().endpoints[0]
        let transports = try InProcessTransportProvider(
            server: FakeKurrentDB(endpoint: endpoint, appendMessages: appendRequest.count, readResponses: readResponses)
        )
        let client = try GRPCClient(transport: AnyClientTransport(transports.makeTransport(for: endpoint)))
        // Runs until the process exits: each benchmark runs in its own process.
        _ = Task { try await client.runConnections() }
        streams = StreamsService.Client(wrapping: client)
        self.appendRequest = appendRequest
        self.readRequest = readRequest
    }

    /// Sends the request messages of one append and returns the response.
    func append() async throws -> EventStore_Client_Streams_AppendResp {
        let messages = appendRequest
        return try await streams.append(request: StreamingClientRequest { writer in
            try await writer.write(contentsOf: messages)
        })
    }

    /// Sends the read request and returns how many response messages arrived.
    func read() async throws -> Int {
        try await streams.read(request: ClientRequest(message: readRequest)) { response in
            var count = 0
            for try await message in response.messages {
                blackHole(message)
                count += 1
            }
            return count
        }
    }

    /// Appends `count` events of 100 bytes per call: the request messages the SDK sends.
    static func appending(_ count: Int) async throws -> Self {
        let events = (0 ..< count).map { _ in EventData(eventType: "OrderPlaced", data: payload) }
        let fixture = try Self(appendRequest: Streams<SpecifiedStream>.Append(to: "orders-abc-123", events: events).requestMessages())
        guard case .success? = try await fixture.append().result else {
            throw FixtureError("the warm-up append did not succeed")
        }
        return fixture
    }

    /// Reads a stream of `count` events of 100 bytes per call: the request the SDK sends for `read()`.
    static func reading(_ count: Int) async throws -> Self {
        let fixture = try Self(
            readResponses: serializedReadResponses(count: count, payload: payload),
            readRequest: Streams<SpecifiedStream>.Read(from: "orders-abc-123", options: .init()).requestMessage()
        )
        let received = try await fixture.read()
        guard received == count else {
            throw FixtureError("the warm-up read returned \(received) messages")
        }
        return fixture
    }
}

private struct FixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
