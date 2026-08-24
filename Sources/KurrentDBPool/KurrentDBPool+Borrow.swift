import KurrentDB

extension KurrentDBPool {
    /// package——外部呼叫端不能直接叫這個，只能透過 public 的
    /// withBorrowedClient(_:)。KurrentDBClient 本身沒有被 extension 過，
    /// 這裡直接由 KurrentDBPool 負責租約 + 建構 + 包裝，一次做完。
    ///
    /// acquire() 只保證「帳本上這台沒被別人租」，不保證「這台真的連得上」——
    /// 拿到 lease 後先用 client.readCluster()（KurrentDBClient 既有的 public API，
    /// 跟 NodeSelector 內部探測用的是同一支 gossip 呼叫）做一次 ack。失敗的候選人
    /// 先扣住不放回 idle pool（避免馬上又抽到同一台白測一次），等這次 borrow()
    /// 整個結束才 giveBack，讓它有機會在下一次呼叫時被重新探測。
    ///
    /// 第一個候選人用會排隊等待的 acquire()——池子全忙碌時值得等一次。
    /// 之後每一輪換候選人改用不排隊的 tryAcquire()：如果現在真的沒有別的候選人
    /// 可換，就立刻停止重試，不要去等一個只有「先前被這次呼叫自己扣住的候選人」
    /// 才可能觸發的 release()——那永遠不會發生，等下去就是自己把自己鎖死。
    package static func borrow(numberOfThreads: Int = 1, maxAttempts: Int = 3) async -> BorrowedClient? {
        guard var candidate = await shared.acquire() else { return nil }
        var rejected: [Lease] = []

        for _ in 0..<maxAttempts {
            let client = KurrentDBClient(settings: candidate.settings, numberOfThreads: numberOfThreads)
            if let members = try? await client.readCluster(), members.contains(where: \.isAlive) {
                for lease in rejected { await lease.giveBack() }
                return BorrowedClient(client: client, lease: candidate)
            }
            rejected.append(candidate)

            guard let next = await shared.tryAcquire() else { break }
            candidate = next
        }

        for lease in rejected { await lease.giveBack() }
        return nil
    }
}
