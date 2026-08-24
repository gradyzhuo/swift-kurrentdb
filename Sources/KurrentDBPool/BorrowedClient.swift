import KurrentDB
import Synchronization

/// 唯一可能被外部套件看到的型別——withBorrowedClient(_:) 把它交給
/// action closure。client 是 public，呼叫端才能實際用它打 RPC；
/// giveBack() 維持 package，外部呼叫端不會、也不該自己呼叫歸還——
/// withBorrowedClient 已經保證會呼叫。deinit 是保底，只有在沒人呼叫過
/// giveBack() 時才動作，state（Mutex<Bool>）保證兩條路徑加起來只會真的
/// release 一次（跟 KurrentDBClient.isShutdown 同一招，見 KurrentDBClient.swift）。
///
/// 歸還不會讓底層的 KurrentDBClient 變得不能用——KurrentDBClient.shutdown()
/// 只釋放它自己擁有的 EventLoopGroup，並不影響大多數 RPC 路徑，所以呼叫它
/// 沒辦法讓「歸還」變成真正的硬邊界（已用 @available(*, deprecated) 標記，
/// 見 KurrentDBClient.swift），這裡索性不再呼叫。isGivenBack 是唯一的、
/// 讀得到的訊號，呼叫端如果自己把 BorrowedClient（不只是 client）留到
/// withBorrowedClient 範圍以外，該自己檢查這個旗標，而不是預期底層連線會
/// 自動失敗。
public final class BorrowedClient: Sendable {
    public let client: KurrentDBClient
    private let lease: KurrentDBPool.Lease
    private let state = Mutex(false)

    /// 歸還之後為 true。這只是 pool 帳本層級的訊號——底層 client 本身
    /// 沒有被禁止繼續使用，呼叫端要自己遵守「還了就不要再用」。
    public var isGivenBack: Bool { state.withLock { $0 } }

    init(client: KurrentDBClient, lease: KurrentDBPool.Lease) {
        self.client = client
        self.lease = lease
    }

    /// 可以重複呼叫；第二次之後什麼都不做。
    package func giveBack() async {
        let shouldRelease = state.withLock { given in
            defer { given = true }
            return !given
        }
        guard shouldRelease else { return }
        await KurrentDBPool.shared.release(lease)
    }

    deinit {
        guard state.withLock({ !$0 }) else { return }
        let lease = lease
        Task { await KurrentDBPool.shared.release(lease) }
    }
}
