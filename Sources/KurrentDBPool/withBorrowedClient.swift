import KurrentDB

/// 借用範圍剛好等於一個 closure 時用這個：不管 action 正常回傳還是丟錯，
/// 保證在這個函式真正返回之前就已經 giveBack() 完畢——故意不用
/// defer { Task { ... } }，因為那樣沒法保證歸還真的在返回前跑完。
///
/// 這是整個 KurrentDBPool target 唯一 public 的入口。BorrowedClient 因此
/// 也必須是 public（Swift 不允許嵌套型別比外層容器更寬鬆），但它的
/// giveBack()/isGivenBack 維持 package——呼叫端只透過這支函式借用，
/// 不需要也不該自己管歸還。
public func withBorrowedClient<T: Sendable>(
    numberOfThreads: Int = 1,
    maxAttempts: Int = 3,
    _ action: (BorrowedClient) async throws -> T
) async rethrows -> T? {
    guard let borrowed = await KurrentDBPool.borrow(numberOfThreads: numberOfThreads, maxAttempts: maxAttempts) else {
        return nil
    }
    do {
        let result = try await action(borrowed)
        await borrowed.giveBack()
        return result
    } catch {
        await borrowed.giveBack()
        throw error
    }
}
