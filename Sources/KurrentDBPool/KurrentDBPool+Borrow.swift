import GRPCCore
import KurrentDB

extension KurrentDBPool {
    /// package——外部呼叫端不能直接叫這個，只能透過 public 的
    /// withBorrowedClient(_:)。KurrentDBClient 本身沒有被 extension 過，
    /// 這裡直接由 KurrentDBPool 負責租約 + 建構 + 包裝，一次做完。
    ///
    /// acquire() 只保證「帳本上這台沒被別人租」，不保證「這台真的連得上」——
    /// 拿到 lease 後先用一個短命的 ack client 呼叫 readCluster()（KurrentDBClient
    /// 既有的 public API，跟 NodeSelector 內部探測用的是同一支 gossip 呼叫）做一次
    /// 存活確認。失敗的候選人先扣住不放回 idle pool（避免馬上又抽到同一台白測
    /// 一次），等這次 borrow() 整個結束才 giveBack，讓它有機會在下一次呼叫時被
    /// 重新探測。
    ///
    /// ack 判斷條件要跟 NodeSelector.discover 內部真正選節點時用的一樣嚴格：
    /// 只看 isAlive 不夠——一個 .manager/.shuttingDown/.shutdown 狀態的節點也可能
    /// 回報 isAlive == true（gossip 有回應，行程還活著，只是不接受正常 RPC）。
    /// NodeDiscover.discover(candidate:) 會用 notAllowedStates: [.manager,
    /// .shuttingDown, .shutdown] 先把這幾種濾掉，我們這裡的 ack 沒有比照辦理的話，
    /// 會把一個「gossip 通、但實際上不能拿來做事」的節點誤判成活的，讓借用端拿到
    /// 一個第一次真正打 RPC 就會失敗的 client，而不是換下一個候選人重試。
    ///
    /// ack 探測本身要有真的會生效的逾時，不能只依賴 readCluster(timeout:)——
    /// 那個參數最終會被轉丟進 Gossip.read(timeout:)，而 Gossip.read(timeout:)
    /// 的簽名是 `read(timeout _: Duration, ...)`，參數名是 `_`，函式本體完全沒用到，
    /// 是 KurrentDB 既有程式碼裡一個確認過的 bug（不在這個 target 的範圍內修，
    /// 這裡繞過就好）。真正會生效的逾時管道是 KurrentDBClient 建構時的
    /// defaultCallOptions.timeout——readCluster() 內部建構 Gossip 時就是拿這個值
    /// 當作 callOptions，NodeSelector.discover(candidate:) 本身也是靠同一個管道
    /// （callOptions.timeout = settings.gossipTimeout）繞過同一個 bug，這裡照抄
    /// 同一招。沒有這個的話，一個「接受連線但永遠不回應 gossip」的候選人會讓這次
    /// ack 的 await 卡住不動，maxAttempts 完全沒機會前進，候選人的 lease 也永遠
    /// 還不回去。
    ///
    /// 特別注意：這個有限逾時只套用在拿來做 ack 探測的那個短命 client 上，
    /// ack 通過之後真正交給呼叫端的 BorrowedClient 是另一個用預設 CallOptions
    /// 重新建構的 client——不能讓 ack 用的短逾時（通常只有幾秒）變成呼叫端
    /// 之後每一支正常 RPC（可能是比較久的讀寫）也套用的預設逾時。
    package static func borrow(numberOfThreads: Int = 1, maxAttempts: Int = 3) async -> BorrowedClient? {
        guard maxAttempts > 0 else { return nil }
        let unusableStates: [Gossip.VNodeState] = [.manager, .shuttingDown, .shutdown]
        var rejected: [Lease] = []

        for attempt in 0..<maxAttempts {
            let next: Lease?
            if attempt == 0 {
                next = await shared.acquire()
            } else {
                next = await shared.tryAcquire()
            }
            guard let candidate = next else { break }

            var ackCallOptions = CallOptions.defaults
            ackCallOptions.timeout = candidate.settings.gossipTimeout
            let ackClient = KurrentDBClient(settings: candidate.settings, numberOfThreads: 1, defaultCallOptions: ackCallOptions)
            let isReachable = (try? await ackClient.readCluster())
                .map { members in members.contains(where: { $0.isAlive && !unusableStates.contains($0.state) }) }
                ?? false
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
