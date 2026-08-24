# KurrentDBPool 實作規劃

目標:測試（未來也可能是一般使用端）能從多個彼此獨立、資料不同步的 KurrentDB 實例中安全借用一台,
用完歸還,不會有兩個持有者同時獨占同一台。獨立成新 target `KurrentDBPool`,不動 `Sources/KurrentDB/**`。

## 背景

`ClientSettings.clusterMode`(`standalone`/`dns`/`seeds`)描述的都是「同一份資料的複本,連誰都一樣」,
所以 `NodeSelector`/`withRetry` 失敗時能安全轉連別台。測試隔離要的是反過來:多台資料互不相干,
連錯就是連錯,retry/invalidate 換節點在這裡是危險的行為。這是不把這個機制塞進 `TopologyClusterMode`
的核心理由——兩者共用「從清單選一個」的表面,但底下的正確性假設完全相反。

參考姊妹專案 OpportunityContext 的 `Tests/OpportunityContextTests/TestDBPool.swift`:idle/busy 狀態 +
`CheckedContinuation` 佇列的 actor 設計已經驗證過,直接借用核心機制。

## 設計決定(已拍板)

1. **獨立 target `KurrentDBPool`**,依賴 `KurrentDB`,`Package.swift` 加對應的 `.library(...)` product
   (因為 `withBorrowedClient` 要 public,見下方存取層級)。
2. **動態 add/remove**:成員存 `[MemberID: Member]` + 插入順序陣列,不是建構時固定的陣列/index——
   支援執行期加入新 DB;`remove()` 對忙碌中的成員先標記 `pendingRemoval`,等它 `release()` 才真的拿掉,
   不強行打斷持有者。
3. **互斥用 actor,不是靠 ack**:標記 idle / 喚醒 waiter 都在同一個 actor turn 內完成(中間沒有 `await`),
   race condition 結構上不存在,不需要額外機制補強。
4. **borrow-level 存活 ack**:`acquire()` 只保證帳本沒衝突,不保證連得上。`borrow()` 拿到候選人後用
   `KurrentDBClient.readCluster()`(public,跟 `NodeSelector` 內部探測用同一支 gossip 呼叫)確認 alive,
   失敗換下一個候選人,上限 `maxAttempts`(預設 3)。被拒絕的候選人先扣在區域變數裡、不立刻還回池子,
   避免同一次呼叫馬上又抽到同一台白測。**不**額外碰 `ServerFeatures.getSupportedMethods()`——它跟
   `Gossip` 的 init 都是 `internal`,從外部 target 叫不到;也**不**用 `KurrentDBClient.selector`
   (雖然 `package` 存取層級技術上看得到,但那是實作細節,故意不依賴)。
5. **歸還機制**:`BorrowedClient.giveBack()` 是顯式、可重複呼叫(idempotent)的主要歸還路徑,連帶
   `client.shutdown()`——歸還變成硬邊界,還了之後繼續用 `client` 會直接拿到連線錯誤,不會有兩個
   `KurrentDBClient` 同時連著同一台 DB。`deinit` 降級成保底(沒人呼叫過 `giveBack()` 時才動作)。
   兩條路徑用 `state: Mutex<Bool>` 保證只真的執行一次(照抄 `KurrentDBClient.isShutdown` 的手法)。
6. **`withBorrowedClient(_:)` 是模組層級自由函式,不是 `KurrentDBPool` 的 static method**——比照
   `withCheckedContinuation`/`withTaskGroup` 慣例。用明確 `do/catch`(不是 `defer { Task {} }`)保證
   `giveBack()` 在函式返回/丟錯前就已完成。
7. **存取層級只開一個安全出口**:`KurrentDBPool` actor 本身、`MemberID`、`Lease`、
   `add`/`remove`/`acquire`/`release`/`borrow()`、`BorrowedClient.giveBack()`/`isGivenBack` 全部
   `package`——手動介面,忘記歸還就是真的漏了,外部依賴 `swift-kurrentdb` 的專案不該碰到。
   只有 `withBorrowedClient(_:)` 和它必須用到的 `BorrowedClient`(僅 `client` 屬性)是 `public`,
   因為這條路徑保證借用後一定歸還。**技術限制**:Swift 不允許嵌套型別比外層容器更寬鬆,
   所以 `BorrowedClient` 必須是頂層型別,不能嵌在 `KurrentDBPool` 裡面。
8. `ClientSettings.pick()`/`.borrow()` 這個入口**先不做**——之後真的需要再補,`Lease` 已經是為了撐住
   它而存在的型別,不會因為現在拿掉而消失。

## 檔案清單

### 新增(`Sources/KurrentDBPool/`)
- `KurrentDBPool.swift` — actor 本體:`shared`、`MemberID`、`Lease`(含 `giveBack()` 便利方法)、
  `Member`、`add`/`remove`/`acquire`/`release`/`dispatchNextWaiterIfPossible`/`firstIdleID`。全部 `package`。
- `KurrentDBPool+Env.swift` — `settingsFromEnv(key:)` 解析 `KURRENTDB_POOL_URLS`(逗號分隔連線字串,
  `ClientSettings.parse(connectionString:)`,格式錯誤 `fatalError`)。`package`。
- `BorrowedClient.swift` — 頂層型別,`public final class`。`client: KurrentDBClient` public;
  `giveBack()`/`isGivenBack` package;`state: Mutex<Bool>`;`deinit` 保底。
- `KurrentDBPool+Borrow.swift` — `KurrentDBPool.borrow(numberOfThreads:maxAttempts:)`,package,
  含 ack + 重試 + 拒絕候選人暫存。
- `withBorrowedClient.swift` — 頂層自由函式,**public**,整個 target 唯一的 public 入口。

### 修改
- `Package.swift` — 新增 `.library(name: "KurrentDBPool", targets: ["KurrentDBPool"])` product +
  `.target(name: "KurrentDBPool", dependencies: ["KurrentDB"])`。

### 測試
- 新增 `KurrentDBPoolTests` test target。

### 不動
- `Sources/KurrentDB/**` 一行都不改。

## 注意 / 風險

- `borrow()` 裡「先扣住被拒絕的候選人、呼叫結束才 giveBack」這個細節容易在重構時被誤刪成
  「馬上還」——刪了會導致同一次呼叫反覆重測同一台掛掉的節點。
- `deinit` 用 `Task { await ... }` 呼叫 release/shutdown 是 unstructured task,沒有「一定在 process
  結束前跑完」的保證——跟「不設 acquire 逾時」是同一種已接受的取捨,不是新風險,但寫測試時不能假設
  deinit 觸發後租約立刻可見地變回 idle(有非同步延遲)。
- 存取層級這條線很容易在後續加新方法時不小心破功(例如某天想加個方便方法卻標成 `public`)——
  §8 的「存取層級」驗證要用一個真正外部的 SwiftPM 套件試編譯,不能只讀 code review access modifier。

## 驗收

- 單元測試:空池 `nil`;多成員並發 `acquire()` 不阻塞;單一成員第二個 `acquire()` 卡住直到 `release()`;
  `add()` 喚醒 waiter;`remove()` 忙碌成員後 `release()` 真的消失。
- 壓力測試:比照 OpportunityContext,N 成員 + 50 併發 acquire/sleep/release,斷言無重複租借。
- Ack 測試:池中混壞掉的 endpoint,`borrow()` 跳過壞的;全壞時 `maxAttempts` 內回 `nil`;
  同一次呼叫不會立刻重抽剛被拒絕的候選人。
- 歸還語意:`giveBack()` 連續呼叫第二次 no-op;只 `deinit` 不呼叫 `giveBack()` 租約仍會釋放;
  `withBorrowedClient` 丟錯時 rethrow 前 `giveBack()` 已完成;歸還後打 RPC 拋連線錯誤,`isGivenBack` 讀到 `true`。
- 整合驗證:兩個本機容器,`KurrentDBPool.borrow()` 各自 append,互相讀不到對方寫的事件。
- 回歸檢查:不 `import KurrentDBPool` 的既有程式碼/測試不受影響。
- 存取層級:外部 SwiftPM 套件依賴 `KurrentDBPool` product,`withBorrowedClient { borrowed in borrowed.client... }`
  要能編譯;`KurrentDBPool.shared`、`.borrow()`、`Lease`、`borrowed.giveBack()`、`borrowed.isGivenBack`
  都要編譯失敗。
