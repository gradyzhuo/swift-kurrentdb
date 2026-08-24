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
    /// 每一輪迴圈只取一個候選人、當場測完：第一輪用會排隊等待的 acquire()——
    /// 池子全忙碌時值得等一次；之後每一輪換候選人改用不排隊的 tryAcquire()，
    /// 沒有其他候選人可換就立刻停止，不要去等一個只有「先前被這次呼叫自己扣住
    /// 的候選人」才可能觸發的 release()。刻意不在迴圈最後一輪結束後再多取一個
    /// 候選人——那個多拿到的候選人不會被測試、也不會被加進 rejected，會永遠卡在
    /// busy 狀態，是一個真實會發生的租約洩漏。
    package static func borrow(numberOfThreads: Int = 1, maxAttempts: Int = 3) async -> BorrowedClient? {
        guard maxAttempts > 0 else { return nil }
        var rejected: [Lease] = []

        for attempt in 0..<maxAttempts {
            let next: Lease?
            if attempt == 0 {
                next = await shared.acquire()
            } else {
                next = await shared.tryAcquire()
            }
            guard let candidate = next else { break }

            let client = KurrentDBClient(settings: candidate.settings, numberOfThreads: numberOfThreads)
            if let members = try? await client.readCluster(), members.contains(where: \.isAlive) {
                for lease in rejected { await lease.giveBack() }
                return BorrowedClient(client: client, lease: candidate)
            }
            rejected.append(candidate)
        }

        for lease in rejected { await lease.giveBack() }
        return nil
    }
}
