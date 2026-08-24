import KurrentDB

extension KurrentDBPool {
    /// package——外部呼叫端不能直接叫這個，只能透過 public 的
    /// withBorrowedClient(_:)。KurrentDBClient 本身沒有被 extension 過，
    /// 這裡直接由 KurrentDBPool 負責租約 + 建構 + 包裝，一次做完。
    ///
    /// acquire() 只保證「帳本上這台沒被別人租」，不保證「這台真的連得上」——
    /// 拿到 lease 後先用 client.readCluster()（KurrentDBClient 既有的 public API，
    /// 跟 NodeSelector 內部探測用的是同一支 gossip 呼叫）做一次 ack。失敗的候選人
    /// 先扣住不放回 idle pool（避免下一輪 acquire() 馬上又抽到同一台白測一次），
    /// 等這次 borrow() 整個結束才 giveBack，讓它有機會在下一次呼叫時被重新探測。
    package static func borrow(numberOfThreads: Int = 1, maxAttempts: Int = 3) async -> BorrowedClient? {
        var rejected: [Lease] = []
        for _ in 0..<maxAttempts {
            guard let candidate = await shared.acquire() else { break }
            let client = KurrentDBClient(settings: candidate.settings, numberOfThreads: numberOfThreads)
            if let members = try? await client.readCluster(), members.contains(where: \.isAlive) {
                for lease in rejected { await lease.giveBack() }
                return BorrowedClient(client: client, lease: candidate)
            }
            try? client.shutdown()
            rejected.append(candidate)
        }
        for lease in rejected { await lease.giveBack() }
        return nil
    }
}
