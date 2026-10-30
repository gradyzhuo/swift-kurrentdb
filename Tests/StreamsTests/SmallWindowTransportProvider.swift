//
//  SmallWindowTransportProvider.swift
//  swift-kurrentdb
//

import GRPCCore
import GRPCNIOTransportHTTP2
@testable import KurrentDB

/// Builds the client's usual Posix transport, with the settings' transport security, but with
/// an HTTP/2 target window of 65,535 bytes instead of grpc-swift's 8 MiB.
///
/// With the default window a read of a few hundred KiB fits in one window: the server writes
/// every message and END_STREAM at once and the call stops holding a stream slot, however slowly
/// the caller iterates. With this window a read larger than 64 KiB keeps its stream open until
/// the consumer has pulled most of it, which is what tests of the per-connection stream limit
/// (100 on KurrentDB) need.
struct SmallWindowTransportProvider: TransportProvider {
    let transportSecurity: HTTP2ClientTransport.Posix.TransportSecurity

    init(settings: ClientSettings) {
        transportSecurity = settings.transportSecurity
    }

    func makeTransport(for endpoint: KurrentDB.Endpoint) throws -> any ClientTransport<AnyClientTransport.Bytes> {
        try HTTP2ClientTransport.Posix.http2NIOPosix(
            target: endpoint.target,
            transportSecurity: transportSecurity,
            config: .defaults { $0.http2.targetWindowSize = 65535 }
        )
    }
}

extension ClientSettings {
    /// These settings with every connection built by ``SmallWindowTransportProvider``.
    func smallHTTP2Window() -> ClientSettings {
        var settings = self
        settings.transportProvider = SmallWindowTransportProvider(settings: self)
        return settings
    }
}
