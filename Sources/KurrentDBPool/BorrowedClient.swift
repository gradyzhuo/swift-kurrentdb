import KurrentDB
import Synchronization

/// 唯一可能被外部套件看到的型別——withBorrowedClient(_:) 把它交給
/// action closure。client 是 public，呼叫端才能實際用它打 RPC；
/// giveBack()/isGivenBack 維持 package，外部呼叫端不會、也不該自己
/// 呼叫歸還——withBorrowedClient 已經保證會呼叫。deinit 是保底，
/// 只有在沒人呼叫過 giveBack() 時才動作，state（Mutex<Bool>）保證
/// 兩條路徑加起來只會真的 release 一次（跟 KurrentDBClient.isShutdown
/// 同一招，見 KurrentDBClient.swift:51）。
public final class BorrowedClient: Sendable {
    public let client: KurrentDBClient
    private let lease: KurrentDBPool.Lease
    private let state = Mutex(false)

    /// 歸還之後 true——client 已經被 shutdown()，繼續用會直接拿到連線錯誤。
    package var isGivenBack: Bool { state.withLock { $0 } }

    init(client: KurrentDBClient, lease: KurrentDBPool.Lease) {
        self.client = client
        self.lease = lease
    }

    /// 可以重複呼叫；第二次之後什麼都不做。歸還時連帶 shutdown() 這個
    /// KurrentDBClient 實例——不這樣做的話,歸還後 client 仍然活著、
    /// 還能繼續打 RPC，等池子把同一台借給下一個人時，就會出現兩個
    /// KurrentDBClient 同時連著同一台 DB 的殭屍連線，等於歸還沒有真的
    /// 生效。shutdown() 讓歸還變成一個硬邊界：還了之後再用 client
    /// 會直接拿到明確的連線錯誤，而不是悄悄繼續動作。
    package func giveBack() async {
        let shouldRelease = state.withLock { given in
            defer { given = true }
            return !given
        }
        guard shouldRelease else { return }
        try? client.shutdown()
        await KurrentDBPool.shared.release(lease)
    }

    deinit {
        guard state.withLock({ !$0 }) else { return }
        try? client.shutdown()
        let lease = lease
        Task { await KurrentDBPool.shared.release(lease) }
    }
}
