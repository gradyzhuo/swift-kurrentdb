//
//  GRPCClientLifecycleCharacterizationTests.swift
//  swift-kurrentdb
//
//  釘住 grpc-swift 2 的連線生命週期行為。這些測試不驗證 KurrentDB 的邏輯,
//  而是記錄我們所依賴的第三方行為 — 若上游改變,這些測試會先失敗。
//
//  已確認的事實:對一個無法連線的目標,`runConnections()` 不會 fail fast —
//  它會無限期地掛著等待,既不拋錯也不返回,沒有任何錯誤可言,自然也沒有
//  「錯誤被吞掉」這回事。唯一能讓它結束的手段,是取消執行它的 Task;
//  取消後那次呼叫本身會「正常返回」(不拋 CancellationError,也不拋任何
//  其他錯誤),且 client 會進入 stopped 狀態。因此本檔案不驗證「會拋錯」
//  (那不是事實),而是驗證「取消能讓它結束,結束方式是正常返回,且結束後
//  client 已經 stopped」。
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

    /// 對無法連線的目標呼叫 `runConnections()` 會無限期地等待 — 這件事本身
    /// 無法在不使用 wall-clock 的情況下斷言(「永遠不結束」不是一個能被
    /// `#expect` 驗證的條件)。唯一已驗證能讓它結束的方式,是取消執行它的
    /// Task —— grpc-swift 官方文件(`GRPCClient.swift:212`)也是這樣寫的:
    /// 「If you need to abruptly stop all work you should cancel the task
    /// executing this method.」
    ///
    /// 這個測試釘住三件事,且每一件都在毫秒等級內完成(不靠時間上限判斷):
    /// 1. 取消能解除阻塞 —— `task.value` 會返回,而不是卡住。
    /// 2. 被取消的那次 `runConnections()` 呼叫本身「正常返回」,不拋出
    ///    `CancellationError`,也不拋出任何其他錯誤(以探測性測試實際執行
    ///    三次確認,結果一致)。這對 Task 4 的生產程式碼修正很重要:呼叫端
    ///    不能靠 `catch is CancellationError` 分辨「因取消而收尾」,因為
    ///    根本不會拋錯。
    /// 3. 取消之後 client 進入 stopped 狀態 —— 第二次呼叫 `runConnections()`
    ///    必定拋錯,證實 client 只能執行一次。
    @Test("連線 Task 被取消後,呼叫本身正常返回(不拋錯),client 進入 stopped 狀態")
    func cancellingConnectionTaskStopsClient() async throws {
        let client = GRPCClient(transport: try unreachableTransport())
        let task = Task { try await client.runConnections() }
        task.cancel()

        // 被取消的第一次呼叫:正常返回,不拋錯(已用探測性測試驗證 3 次,結果一致)。
        try await task.value

        // 再次 run 應拋錯:client 只能執行一次,取消已讓它進入 stopped 狀態。
        await #expect(throws: (any Error).self) {
            try await client.runConnections()
        }
    }
}
