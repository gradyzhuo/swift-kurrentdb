//
//  GRPCClientLifecycleCharacterizationTests.swift
//  swift-kurrentdb
//
//  釘住 grpc-swift 2 的連線生命週期行為。這些測試不驗證 KurrentDB 的邏輯,
//  而是記錄我們所依賴的第三方行為 — 若上游改變,這些測試會先失敗。
//

import Testing
import GRPCCore
import GRPCNIOTransportHTTP2
@testable import KurrentDB

@Suite("GRPCClient 連線生命週期特性", .serialized, .timeLimit(.minutes(1)))
struct GRPCClientLifecycleCharacterizationTests {

    /// 指向一個必定無法連線的位址(TEST-NET-1,RFC 5737 保留,不可路由)。
    /// 沿用 repo 既有的 `Endpoint.target` 與 `.http2NIOPosix`,與
    /// `GRPCClient+Additions.swift:17-20` 的建構方式一致。
    private func unreachableTransport() throws -> HTTP2ClientTransport.Posix {
        let endpoint = Endpoint(host: "192.0.2.1", port: 2113)
        return try .http2NIOPosix(
            target: endpoint.target,
            transportSecurity: .plaintext
        )
    }

    @Test("runConnections() 對無法連線的目標會拋錯,而非無限等待")
    func runConnectionsThrowsOnUnreachable() async throws {
        let client = GRPCClient(transport: try unreachableTransport())
        await #expect(throws: (any Error).self) {
            try await client.runConnections()
        }
    }

    @Test("連線 Task 被取消後,client 進入 stopped 狀態")
    func cancellingConnectionTaskStopsClient() async throws {
        let client = GRPCClient(transport: try unreachableTransport())
        let task = Task { try await client.runConnections() }
        task.cancel()
        _ = try? await task.value
        // 再次 run 應拋錯:client 只能執行一次
        await #expect(throws: (any Error).self) {
            try await client.runConnections()
        }
    }
}
