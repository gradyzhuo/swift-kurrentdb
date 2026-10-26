//
//  TransportProvider.swift
//  KurrentCore
//

import GRPCCore
import GRPCNIOTransportHTTP2

/// Builds the client transport for each connection a client opens.
///
/// `ClientSettings.transportProvider` is `nil` by default: every connection is then HTTP/2 over
/// Posix sockets, configured from the settings (TLS, keepalive). A provider replaces that
/// transport, for example with an in-process one, so benchmarks and tests can run the whole
/// client against a server in the same process. ``ConnectionProvider`` calls it every time it
/// opens a connection: for the first shared call to an endpoint, for each dedicated call, and
/// again after an idle shared connection was retired.
package protocol TransportProvider: Sendable {
    /// Returns a new transport to `endpoint` that has not connected yet.
    func makeTransport(for endpoint: Endpoint) throws -> any ClientTransport<AnyClientTransport.Bytes>
}

/// The one transport type every client connection uses, whatever built it.
///
/// Usecases and generated service clients are generic over their transport, but the connection
/// cache holds one concrete type, so the transport is erased here instead of making
/// `KurrentDBClient` generic. The box forwards the calls grpc-swift makes on a transport:
/// `config(forMethod:)` and `withStream` for every RPC, `connect` for every connection. The
/// request and response streams pass through untouched, so messages cost nothing extra. The bytes
/// type stays the Posix transport's, so the default path converts nothing; a transport with other
/// bytes has to convert them itself.
package struct AnyClientTransport: ClientTransport {
    package typealias Bytes = HTTP2ClientTransport.Posix.Bytes

    private let base: any ClientTransport<Bytes>

    package init(_ base: some ClientTransport<Bytes>) {
        self.base = base
    }

    package var retryThrottle: RetryThrottle? {
        base.retryThrottle
    }

    package func connect() async throws {
        try await base.connect()
    }

    package func beginGracefulShutdown() {
        base.beginGracefulShutdown()
    }

    package func withStream<T: Sendable>(
        descriptor: MethodDescriptor,
        options: CallOptions,
        _ closure: (_ stream: RPCStream<Inbound, Outbound>, _ context: ClientContext) async throws -> T
    ) async throws -> T {
        try await base.withStream(descriptor: descriptor, options: options, closure)
    }

    package func config(forMethod descriptor: MethodDescriptor) -> MethodConfig? {
        base.config(forMethod: descriptor)
    }
}
