import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCInProcessTransport
import KurrentDB

// An in-process stand-in for one KurrentDB node, so the client benchmarks run a real
// `KurrentDBClient` without a server. It answers discovery (gossip, server features), append and
// read with responses serialized in advance, keeps no state and never parses what it is sent:
// what the benchmarks measure is the client. It does take every request whole before answering,
// as a node does, and fails a call whose request does not carry the expected number of messages,
// so a client that sends less fails the benchmark instead of measuring less work.

private typealias GossipService = EventStore_Client_Gossip_Gossip
private typealias ServerFeaturesService = EventStore_Client_ServerFeatures_ServerFeatures
private typealias StreamsService = EventStore_Client_Streams_Streams

/// Answers the RPCs a client makes to discover a node and to append to and read one stream.
struct FakeKurrentDB: RegistrableRPCService {
    private let gossip: [UInt8]
    private let serverFeatures: [UInt8]
    private let appendMessages: Int
    private let appendResponse: [UInt8]
    private let readResponses: [[UInt8]]

    /// - Parameters:
    ///   - endpoint: The leader gossip reports; the client connects to it after discovery.
    ///   - appendMessages: How many request messages every append carries: its options, then one
    ///     per event. An append with any other number fails.
    ///   - readResponses: The serialized `ReadResp` messages every read streams back, in order.
    init(endpoint: Endpoint, appendMessages: Int, readResponses: [[UInt8]] = []) throws {
        gossip = try EventStore_Client_Gossip_ClusterInfo.with {
            $0.members = [.with {
                $0.instanceID = .with { $0.value = .string(UUID().uuidString) }
                $0.state = .leader
                $0.isAlive = true
                $0.httpEndPoint = .with {
                    $0.address = endpoint.host
                    $0.port = endpoint.port
                }
            }]
        }.serializedBytes()
        serverFeatures = try EventStore_Client_ServerFeatures_SupportedMethods.with {
            $0.eventStoreServerVersion = "26.1.0"
            $0.methods = [StreamsService.Method.Append.descriptor, StreamsService.Method.Read.descriptor].map { method in
                .with {
                    $0.serviceName = method.service.fullyQualifiedService
                    $0.methodName = method.method
                }
            }
        }.serializedBytes()
        appendResponse = try EventStore_Client_Streams_AppendResp.with {
            $0.success = .with {
                $0.currentRevision = 0
                $0.position = .with {
                    $0.commitPosition = 0
                    $0.preparePosition = 0
                }
            }
        }.serializedBytes()
        self.appendMessages = appendMessages
        self.readResponses = readResponses
    }

    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        let gossip = gossip
        let serverFeatures = serverFeatures
        let appendMessages = appendMessages
        let appendResponse = appendResponse
        let readResponses = readResponses

        router.registerHandler(
            forMethod: GossipService.Method.Read.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { request, _ in
            try await request.expectMessages(1)
            return .responding(with: [gossip])
        }
        router.registerHandler(
            forMethod: ServerFeaturesService.Method.GetSupportedMethods.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { request, _ in
            try await request.expectMessages(1)
            return .responding(with: [serverFeatures])
        }
        router.registerHandler(
            forMethod: StreamsService.Method.Append.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { request, _ in
            try await request.expectMessages(appendMessages)
            return .responding(with: [appendResponse])
        }
        router.registerHandler(
            forMethod: StreamsService.Method.Read.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { request, _ in
            try await request.expectMessages(1)
            return .responding(with: readResponses)
        }
    }
}

/// Connects every connection a client opens to its own in-process server answering as `server`.
struct InProcessTransportProvider: TransportProvider {
    let server: FakeKurrentDB

    func makeTransport(for _: Endpoint) throws -> any ClientTransport<AnyClientTransport.Bytes> {
        InProcessConnection(serving: server)
    }
}

/// One client connection with its own in-process server: `connect()` runs the server next to the
/// client side and stops it when the connection ends, so a client's shutdown also stops its
/// servers.
///
/// grpc-swift's in-process transport carries `[UInt8]`, while `AnyClientTransport` takes the
/// Posix transport's bytes, so every message is copied once on its way in and once on its way out.
/// The client benchmarks include that copy; the Posix transport has its own instead.
///
/// Requests reach the server without their `grpc-timeout` header. With it, the in-process server
/// would run a deadline timer of its own in the measured process; a node runs that timer on its
/// own machine. Dropping the header copies the request metadata of a call with a deadline.
private struct InProcessConnection: ClientTransport {
    typealias Bytes = AnyClientTransport.Bytes

    private let client: InProcessTransport.Client
    private let server: GRPCServer<InProcessTransport.Server>

    init(serving service: some RegistrableRPCService) {
        let transport = InProcessTransport()
        client = transport.client
        server = GRPCServer(transport: transport.server, services: [service])
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
        try await client.withStream(descriptor: descriptor, options: options) { stream, context in
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

/// Drops a request message unread: the fake server's answers do not depend on it.
private struct DiscardingDeserializer: MessageDeserializer {
    func deserialize<Bytes: GRPCContiguousBytes>(_: Bytes) throws {}
}

/// Sends a response that was serialized in advance, so the server adds no protobuf work.
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
            // Removing copies the shared metadata, so only a call with a deadline pays for it.
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
