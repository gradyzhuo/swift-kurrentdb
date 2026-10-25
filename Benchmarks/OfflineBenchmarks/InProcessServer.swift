import Foundation
import GRPCCore
import GRPCEncapsulates
import GRPCInProcessTransport
import KurrentDB

// An in-process stand-in for one KurrentDB node, so the client benchmarks run a real
// `KurrentDBClient` without a server. It answers discovery (gossip, server features), append and
// read with responses serialized in advance, keeps no state and never parses what it is sent:
// what the benchmarks measure is the client.

private typealias GossipService = EventStore_Client_Gossip_Gossip
private typealias ServerFeaturesService = EventStore_Client_ServerFeatures_ServerFeatures
private typealias StreamsService = EventStore_Client_Streams_Streams

/// Answers the RPCs a client makes to discover a node and to append to and read one stream.
struct FakeKurrentDB: RegistrableRPCService {
    private let gossip: [UInt8]
    private let serverFeatures: [UInt8]
    private let appendResponse: [UInt8]
    private let readResponses: [[UInt8]]

    /// - Parameters:
    ///   - endpoint: The leader gossip reports; the client connects to it after discovery.
    ///   - readResponses: The serialized `ReadResp` messages every read streams back, in order.
    init(endpoint: Endpoint, readResponses: [[UInt8]] = []) throws {
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
        self.readResponses = readResponses
    }

    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        let gossip = gossip
        let serverFeatures = serverFeatures
        let appendResponse = appendResponse
        let readResponses = readResponses

        router.registerHandler(
            forMethod: GossipService.Method.Read.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { _, _ in
            .responding(with: [gossip])
        }
        router.registerHandler(
            forMethod: ServerFeaturesService.Method.GetSupportedMethods.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { _, _ in
            .responding(with: [serverFeatures])
        }
        router.registerHandler(
            forMethod: StreamsService.Method.Append.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { request, _ in
            // Client streaming: take every request message before answering, as the server does.
            for try await _ in request.messages {}
            return .responding(with: [appendResponse])
        }
        router.registerHandler(
            forMethod: StreamsService.Method.Read.descriptor,
            deserializer: DiscardingDeserializer(),
            serializer: PreSerializedSerializer()
        ) { _, _ in
            .responding(with: readResponses)
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

/// Writes request parts to the in-process transport, converting their bytes on the way.
private struct ConvertingWriter: ClosableRPCWriterProtocol {
    let base: InProcessTransport.Client.Outbound

    func write(_ element: RPCRequestPart<AnyClientTransport.Bytes>) async throws {
        try await base.write(element.converted())
    }

    func write(contentsOf elements: some Sequence<RPCRequestPart<AnyClientTransport.Bytes>>) async throws {
        try await base.write(contentsOf: elements.map { $0.converted() })
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
    /// The same bytes in another bytes type: one allocation and one copy.
    fileprivate func converted<Other: GRPCContiguousBytes>() -> Other {
        withUnsafeBytes { Other($0) }
    }
}

extension RPCRequestPart {
    fileprivate func converted<Other: GRPCContiguousBytes>() -> RPCRequestPart<Other> {
        switch self {
        case let .metadata(metadata): .metadata(metadata)
        case let .message(bytes): .message(bytes.converted())
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
