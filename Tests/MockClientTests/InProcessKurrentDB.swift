//
//  InProcessKurrentDB.swift
//  swift-kurrentdb
//
//  A fake KurrentDB node on grpc-swift's in-process transport, so read delivery can be tested
//  without a server. The transport bridging below (`InProcessConnection`, `ConvertingWriter` and
//  the bytes conversions) is a copy of `Benchmarks/OfflineBenchmarks/InProcessServer.swift`: the
//  benchmark target is not a dependency of the tests. Keep the two in step.
//

import Foundation
import GRPCCore
import GRPCInProcessTransport
import Synchronization
@testable import KurrentDB

private typealias GossipService = Gossip.Read.ServiceClient.UnderlyingService
private typealias ServerFeaturesService = ServerFeatures.GetSupportedMethods.ServiceClient.UnderlyingService
private typealias StreamsService = Streams<SpecifiedStream>.Read.ServiceClient.UnderlyingService

/// One fake node behind `ClientSettings.transportProvider`: answers gossip and server features for
/// `endpoint`, and serves every `Streams.Read` call per `script`.
///
/// Every connection a client opens gets its own in-process server, and one fake can serve several
/// clients; `readsStarted` counts the read calls of all of them. The fake never parses a request:
/// a read of any stream, forward or backward, from `$all` or not, gets the same script.
///
/// The in-process transport does not tell the server that a client cancelled one call (a deadline,
/// a `break`, a cancelled task): the client's side of the call ends, while a `.hold` handler stays
/// suspended until the connection it runs on closes, which `KurrentDBClient.shutdown()` or an idle
/// sweep does. Only the client's side is what these tests observe.
///
/// `openStreams` counts the RPC streams the client has open on the fake, over all its connections
/// (discovery calls included; they end at once). A stream counts from when it gets a slot until
/// the transport's `withStream` returns on the client, which grpc-swift does only after the
/// call's response handling has ended. So a client that hands back its lease before its RPC task
/// has finished still leaves the count above 0, and `eventually { fake.openStreams == 0 }` after
/// a read is how a test shows that nothing leaked. The count is the client's side: with `.hold`, a
/// call the client abandons leaves the count when the client's side ends (as of grpc-swift 2.4),
/// while its server handler stays suspended until the connection closes, which the count does not
/// show. Because that depends on how the client side of an abandoned call ends, assert promptness
/// with `.end` or other finite scripts, and with `.hold` close the connection (`shutdown()`)
/// before expecting 0.
///
/// `maxConcurrentStreams` limits the streams open at once on each connection, as a node's HTTP/2
/// `SETTINGS_MAX_CONCURRENT_STREAMS` (100 on KurrentDB) does: a further stream waits, in order,
/// until one on the same connection ends, or until its task is cancelled (a deadline included).
/// `nil`, the default, means no limit.
final class InProcessKurrentDB: TransportProvider, Sendable {
    /// What every `Streams.Read` call answers.
    struct ReadScript: Sendable {
        /// How a read call ends once `messages` are written.
        enum Ending: Sendable {
            /// The call ends successfully.
            case end
            /// The call ends with this status.
            case error(RPCError)
            /// The call stays open until it is cancelled (see the type's note on cancellation).
            case hold
        }

        /// Sent in order, after `acceptDelay`.
        var messages: [Streams<SpecifiedStream>.Read.UnderlyingResponse]
        var ending: Ending
        /// How long the handler sleeps before it returns the response, whose headers are what the
        /// client sees as the call being accepted.
        var acceptDelay: Duration = .zero

        /// `count` events of stream `"orders"` with revisions `0..<count`, each an `"OrderPlaced"`
        /// event with a 100-byte JSON payload, then `ending`.
        static func events(_ count: Int, then ending: Ending = .end) -> ReadScript {
            ReadScript(messages: (0 ..< count).map(Self.event(revision:)), ending: ending)
        }

        private static let payload: Data = {
            let prefix = #"{"orderId":"abc-123","amount":99.99,"items":3,"note":""#
            let suffix = #""}"#
            let padding = String(repeating: "a", count: 100 - prefix.utf8.count - suffix.utf8.count)
            return Data((prefix + padding + suffix).utf8)
        }()

        private static func event(revision: Int) -> Streams<SpecifiedStream>.Read.UnderlyingResponse {
            .with {
                $0.event = .with {
                    $0.event = .with {
                        $0.id = .with { $0.value = .string(UUID().uuidString) }
                        $0.streamIdentifier = .with { $0.streamName = Data("orders".utf8) }
                        $0.streamRevision = UInt64(revision)
                        $0.preparePosition = UInt64(revision * 512)
                        $0.commitPosition = UInt64(revision * 512)
                        $0.metadata = [
                            "type": "OrderPlaced",
                            "content-type": "application/json",
                            "created": "17612345678901234",
                        ]
                        $0.data = payload
                    }
                    $0.commitPosition = UInt64(revision * 512)
                }
            }
        }
    }

    let endpoint: Endpoint
    /// The most streams open at once on one connection; `nil` for no limit.
    let maxConcurrentStreams: Int?
    private let service: Service
    private let openStreamCount = Mutex(0)

    init(endpoint: Endpoint = Endpoint(host: "127.0.0.1", port: 2113), read: ReadScript, maxConcurrentStreams: Int? = nil) {
        precondition(maxConcurrentStreams.map { $0 > 0 } ?? true, "maxConcurrentStreams must be positive")
        self.endpoint = endpoint
        self.maxConcurrentStreams = maxConcurrentStreams
        service = Service(endpoint: endpoint, read: read)
    }

    /// `ClientSettings.localhost()`-style settings for `endpoint` (insecure, standalone), with
    /// `nodeCacheTTL` 1 h and `transportProvider` set to this fake.
    var settings: ClientSettings {
        var settings = ClientSettings(
            clusterMode: .standalone(endpoint: endpoint),
            secure: false,
            tlsVerifyCert: false,
            nodeCacheTTL: .seconds(3600)
        )
        settings.transportProvider = self
        return settings
    }

    /// How many `Streams.Read` calls the fake has started so far.
    var readsStarted: Int {
        service.readsStarted.withLock { $0 }
    }

    /// How many RPC streams the client has open on the fake right now, over all its connections.
    var openStreams: Int {
        openStreamCount.withLock { $0 }
    }

    fileprivate func streamOpened() {
        openStreamCount.withLock { $0 += 1 }
    }

    fileprivate func streamClosed() {
        openStreamCount.withLock { $0 -= 1 }
    }

    func makeTransport(for _: Endpoint) throws -> any ClientTransport<AnyClientTransport.Bytes> {
        InProcessConnection(serving: service, fake: self, slots: StreamSlots(limit: maxConcurrentStreams))
    }
}

extension InProcessKurrentDB {
    /// The RPCs a client makes to discover the node and to read from it.
    private final class Service: RegistrableRPCService, Sendable {
        let endpoint: Endpoint
        let read: ReadScript
        let readsStarted = Mutex(0)

        init(endpoint: Endpoint, read: ReadScript) {
            self.endpoint = endpoint
            self.read = read
        }

        func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
            router.registerHandler(
                forMethod: GossipService.Method.Read.descriptor,
                deserializer: DiscardingDeserializer(),
                serializer: PreSerializedSerializer()
            ) { [endpoint] request, _ in
                try await request.expectMessages(1)
                let info = GossipService.Method.Read.Output.with {
                    $0.members = [.with {
                        $0.instanceID = .with { $0.value = .string(UUID().uuidString) }
                        $0.state = .leader
                        $0.isAlive = true
                        $0.httpEndPoint = .with {
                            $0.address = endpoint.host
                            $0.port = endpoint.port
                        }
                    }]
                }
                return try .responding(with: [info.serializedBytes()])
            }
            router.registerHandler(
                forMethod: ServerFeaturesService.Method.GetSupportedMethods.descriptor,
                deserializer: DiscardingDeserializer(),
                serializer: PreSerializedSerializer()
            ) { request, _ in
                try await request.expectMessages(1)
                // Only reads are served; subscriptions to a stream or to $all use the Read RPC too.
                let methods = [StreamsService.Method.Read.descriptor]
                let supported = ServerFeaturesService.Method.GetSupportedMethods.Output.with {
                    $0.eventStoreServerVersion = "26.1.0"
                    $0.methods = methods.map { method in
                        .with {
                            $0.serviceName = method.service.fullyQualifiedService
                            $0.methodName = method.method
                        }
                    }
                }
                return try .responding(with: [supported.serializedBytes()])
            }
            router.registerHandler(
                forMethod: StreamsService.Method.Read.descriptor,
                deserializer: DiscardingDeserializer(),
                serializer: PreSerializedSerializer()
            ) { request, _ in
                self.readsStarted.withLock { $0 += 1 }
                let read = self.read
                try await request.expectMessages(1)
                let messages: [[UInt8]] = try read.messages.map { try $0.serializedBytes() }
                if read.acceptDelay > .zero {
                    try await Task.sleep(for: read.acceptDelay)
                }
                return StreamingServerResponse(metadata: [:]) { [ending = read.ending] writer in
                    try await writer.write(contentsOf: messages)
                    switch ending {
                    case .end:
                        break
                    case let .error(error):
                        throw error
                    case .hold:
                        try await Task.sleep(for: .seconds(3600))
                    }
                    return [:]
                }
            }
        }
    }
}

/// The stream slots of one connection: with a `limit`, a stream beyond it waits, first come first
/// served, until a slot is released or its task is cancelled.
private final class StreamSlots: Sendable {
    private struct State {
        var open = 0
        var nextWaiter: UInt64 = 0
        var waiters: [(id: UInt64, continuation: CheckedContinuation<Void, any Error>)] = []
    }

    private let limit: Int?
    private let state = Mutex(State())

    init(limit: Int?) {
        self.limit = limit
    }

    func acquire() async throws {
        guard let limit else { return }
        let waiter: UInt64? = state.withLock { state in
            if state.open < limit {
                state.open += 1
                return nil
            }
            defer { state.nextWaiter += 1 }
            return state.nextWaiter
        }
        guard let id = waiter else { return }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                // Checked under the lock: a cancellation that ran before this registration found no
                // waiter to resume, but has already set the flag.
                let cancelled = state.withLock { state in
                    if Task.isCancelled { return true }
                    state.waiters.append((id, continuation))
                    return false
                }
                if cancelled {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = state.withLock { state in
                state.waiters.firstIndex { $0.id == id }.map { state.waiters.remove(at: $0).continuation }
            }
            continuation?.resume(throwing: CancellationError())
        }
    }

    /// Hands the slot to the first waiter, or frees it.
    func release() {
        guard limit != nil else { return }
        let next = state.withLock { state in
            if state.waiters.isEmpty {
                state.open -= 1
                return nil as CheckedContinuation<Void, any Error>?
            }
            return state.waiters.removeFirst().continuation
        }
        next?.resume()
    }
}

// MARK: - Transport bridging (a copy of Benchmarks/OfflineBenchmarks/InProcessServer.swift)

/// One client connection with its own in-process server: `connect()` runs the server next to the
/// client side and stops it when the connection ends, so a client's shutdown also stops its
/// servers (and cancels the handlers still running on them).
///
/// grpc-swift's in-process transport carries `[UInt8]`, while `AnyClientTransport` takes the
/// Posix transport's bytes, so every message is copied once on its way in and once on its way out.
///
/// Requests reach the server without their `grpc-timeout` header, so a call's deadline is enforced
/// by the client alone, as it is against a real node across a network.
private struct InProcessConnection: ClientTransport {
    typealias Bytes = AnyClientTransport.Bytes

    private let client: InProcessTransport.Client
    private let server: GRPCServer<InProcessTransport.Server>
    // Not in the benchmark's copy: the fake's stream count and this connection's stream limit.
    private let fake: InProcessKurrentDB
    private let slots: StreamSlots

    init(serving service: some RegistrableRPCService, fake: InProcessKurrentDB, slots: StreamSlots) {
        let transport = InProcessTransport()
        client = transport.client
        server = GRPCServer(transport: transport.server, services: [service])
        self.fake = fake
        self.slots = slots
    }

    var retryThrottle: RetryThrottle? {
        client.retryThrottle
    }

    func connect() async throws {
        try await withThrowingDiscardingTaskGroup { group in
            group.addTask { try await server.serve() }
            // Returns once the connection is cancelled or has shut down.
            try await client.connect()
            server.beginGracefulShutdown()
        }
    }

    func beginGracefulShutdown() {
        client.beginGracefulShutdown()
    }

    func withStream<T: Sendable>(
        descriptor: MethodDescriptor,
        options: CallOptions,
        _ closure: (_ stream: RPCStream<Inbound, Outbound>, _ context: ClientContext) async throws -> T
    ) async throws -> T {
        try await slots.acquire()
        fake.streamOpened()
        defer {
            fake.streamClosed()
            slots.release()
        }
        return try await client.withStream(descriptor: descriptor, options: options) { stream, context in
            let converted = RPCStream(
                descriptor: stream.descriptor,
                inbound: Inbound(wrapping: stream.inbound.map { $0.converted() }),
                outbound: Outbound(wrapping: ConvertingWriter(base: stream.outbound))
            )
            return try await closure(converted, context)
        }
    }

    func config(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
        client.config(forMethod: descriptor)
    }
}

/// Writes request parts to the in-process transport, as `RPCRequestPart.forInProcessServer()`
/// makes them.
private struct ConvertingWriter: ClosableRPCWriterProtocol {
    let base: InProcessTransport.Client.Outbound

    func write(_ element: RPCRequestPart<AnyClientTransport.Bytes>) async throws {
        try await base.write(element.forInProcessServer())
    }

    func write(contentsOf elements: some Sequence<RPCRequestPart<AnyClientTransport.Bytes>>) async throws {
        try await base.write(contentsOf: elements.map { $0.forInProcessServer() })
    }

    func finish() async {
        await base.finish()
    }

    func finish(throwing error: any Error) async {
        await base.finish(throwing: error)
    }
}

/// Drops a request message unread: the fake's answers do not depend on it.
private struct DiscardingDeserializer: MessageDeserializer {
    func deserialize<Bytes: GRPCContiguousBytes>(_: Bytes) throws {}
}

/// Sends a response that was serialized in advance.
private struct PreSerializedSerializer: MessageSerializer {
    func serialize<Bytes: GRPCContiguousBytes>(_ message: [UInt8]) throws -> Bytes {
        Bytes(message)
    }
}

extension StreamingServerRequest {
    /// Waits for the end of the request and checks that it carried `count` messages.
    fileprivate func expectMessages(_ count: Int) async throws {
        var received = 0
        for try await _ in messages {
            received += 1
        }
        guard received == count else {
            throw RPCError(code: .invalidArgument, message: "expected \(count) request messages, received \(received)")
        }
    }
}

extension StreamingServerResponse<[UInt8]> {
    /// A response that writes `messages` in order and ends the call successfully.
    fileprivate static func responding(with messages: [[UInt8]]) -> Self {
        Self { writer in
            try await writer.write(contentsOf: messages)
            return [:]
        }
    }
}

extension GRPCContiguousBytes {
    /// The same bytes in another bytes type: one copy.
    fileprivate func converted<Other: GRPCContiguousBytes>() -> Other {
        withUnsafeBytes { Other($0) }
    }
}

extension RPCRequestPart {
    /// The part as the in-process server takes it: its bytes converted, and its metadata without
    /// `grpc-timeout`.
    fileprivate func forInProcessServer<Other: GRPCContiguousBytes>() -> RPCRequestPart<Other> {
        switch self {
        case var .metadata(metadata):
            if metadata.contains(where: { $0.key == "grpc-timeout" }) {
                metadata.removeAllValues(forKey: "grpc-timeout")
            }
            return .metadata(metadata)
        case let .message(bytes):
            return .message(bytes.converted())
        }
    }
}

extension RPCResponsePart {
    fileprivate func converted<Other: GRPCContiguousBytes>() -> RPCResponsePart<Other> {
        switch self {
        case let .metadata(metadata): .metadata(metadata)
        case let .message(bytes): .message(bytes.converted())
        case let .status(status, trailers): .status(status, trailers)
        }
    }
}
