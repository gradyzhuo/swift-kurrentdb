import KurrentDB

extension KurrentDBPool {
    /// package——外部呼叫端不能直接叫這個，只能透過 public 的
    /// withBorrowedClient(_:)。KurrentDBClient 本身沒有被 extension 過，
    /// 這裡直接由 KurrentDBPool 負責租約 + 建構 + 包裝，一次做完。
    ///
    /// acquire() 只保證「帳本上這台沒被別人租」，不保證「這台真的連得上」——
    /// 拿到 lease 後先用一個短命的 ack client 做一次存活確認。失敗的候選人先
    /// 扣住不放回 idle pool（避免馬上又抽到同一台白測一次），等這次 borrow()
    /// 整個結束才 giveBack，讓它有機會在下一次呼叫時被重新探測。
    ///
    /// ack 用的是 client.selector.select()（package-scoped，跟 KurrentDBPool
    /// 同一個 package 所以看得到），而不是先前用過的 client.readCluster()——
    /// readCluster() 只驗證「gossip seed 本身連得到」，不會驗證 NodeSelector
    /// 實際會選中、拿去打真正 RPC 的那個位址也連得到。這兩件事在 Docker/NAT
    /// 環境下可能不一樣：seed 本身連得到，但 gossip 回報的位址不可達（例如
    /// 容器沒設對外廣播位址，這正是本 target 開發過程中實際踩到、也修過的
    /// 那個問題）——readCluster() 會誤判成活的，交給借用端一個第一次真正打
    /// RPC 就會失敗的 client。selector.select() 跑的是跟 perform() 每次真正
    /// 發 RPC 前一模一樣的路徑（gossip 探測 + endpoint 解析 + ServerFeatures
    /// 確認），是唯一能保證「ack 過了、真正的操作就會成功」的探測方式；
    /// NodeDiscover.discover(candidate:) 內部也已經用 notAllowedStates 濾掉
    /// .manager/.shuttingDown/.shutdown，不用在這裡重複做一次、平白多一份
    /// 可能跟 NodeSelector 本尊邏輯兜不起來的複本。
    ///
    /// select() 本身有界：NodeDiscover.discover(candidate:) 跟 ServerFeatures
    /// 確認都各自用 settings.gossipTimeout 建立自己的 CallOptions（不依賴
    /// KurrentDBClient 建構時傳入的 defaultCallOptions），外層 selectNode()
    /// 再包一層 maxDiscoveryAttempts 次數上限——不會無限期卡住。
    ///
    /// 每一輪迴圈只取一個候選人、當場測完：第一輪用會排隊等待的 acquire()——
    /// 池子全忙碌時值得等一次；之後每一輪換候選人改用不排隊的 tryAcquire()，
    /// 沒有其他候選人可換就立刻停止，不要去等一個只有「先前被這次呼叫自己扣住
    /// 的候選人」才可能觸發的 release()。刻意不在迴圈最後一輪結束後再多取一個
    /// 候選人——那個多拿到的候選人不會被測試、也不會被加進 rejected，會永遠卡在
    /// busy 狀態，是一個真實會發生的租約洩漏。
    ///
    /// 特別注意：ack 用的短命 client 跟真正交給呼叫端的 BorrowedClient 是分開
    /// 建構的兩個實例——ack 過了就直接丟掉那個 client，重新用正常設定建一個給
    /// 呼叫端，不要把 ack 探測沿用的實例繼續交出去。
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

            let ackClient = KurrentDBClient(settings: candidate.settings, numberOfThreads: 1)
            let isReachable = (try? await ackClient.selector.select()) != nil
            try? ackClient.shutdown()

            guard isReachable else {
                rejected.append(candidate)
                continue
            }

            for lease in rejected { await lease.giveBack() }
            let client = KurrentDBClient(settings: candidate.settings, numberOfThreads: numberOfThreads)
            return BorrowedClient(client: client, lease: candidate)
        }

        for lease in rejected { await lease.giveBack() }
        return nil
    }
}
