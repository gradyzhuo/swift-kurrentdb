# 持久訂閱連線生命週期缺陷 — 修正設計

- **日期**:2026-07-20
- **狀態**:設計已核可,尚未實作
- **範圍**:僅限已驗證的失效路徑
- **視覺版本**:`persistent-subscription-lifecycle.html`(圖表完整版)

---

## 1. 問題

`PersistentSubscriptionAdvancedTests` 在 CI 上偶發兩種失敗,共用同一個根因:

| 失敗 | 表現 | 出處 |
|---|---|---|
| A | `testNackWithPark()` 靜默 hang 16 分鐘,留下 orphan `swift-test` process | PR #118 · job 88266932116 |
| B | `testUpdateSubscription()` SIGABRT(signal 6) | PR #119 · job 87397952995 |

兩次皆為 Swift 6.0 / KurrentDB 26.1。**但此關聯不可信** —— workflow 未設 `fail-fast: false`,任一 cell 失敗會取消其餘所有 cell,樣本有系統性偏差。

近期 5 次失敗的 run 中,僅 1 次是真正的測試失敗;其餘 4 次為 `Start KurrentDB cluster` 失敗(環境問題,與 SDK 無關)。分類時必須看失敗步驟,不能看 job 名稱。

## 2. 根因

### 2.0 檔案路徑對照(重要 — 簡寫有歧義)

本文後續以簡寫指稱檔案。**同名檔案在 repo 中不只一份**,實作時務必開對:

| 本文簡寫 | 實際路徑 | 行數 |
|---|---|---|
| `StreamStream.swift` | `Sources/KurrentDB/Core/Additions/Usecase/StreamStream.swift` | 46 |
| `UnaryUnary.swift` | `Sources/KurrentDB/Core/Additions/Usecase/UnaryUnary.swift` | 55 |
| `StreamUnary.swift` | `Sources/KurrentDB/Core/Additions/Usecase/StreamUnary.swift` | 48 |
| `Subscription.swift` | `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.Subscription.swift` | 283 |
| `…SpecifiedStream.Read.swift` | `Sources/KurrentDB/PersistentSubscriptions/Usecase/Specified/PersistentSubscriptions.SpecifiedStream.Read.swift` | — |
| `KurrentError.swift` | `Sources/KurrentDB/Core/Error/KurrentError.swift` | 299 |

**易錯點**:`Sources/GRPCEncapsulates/Usecase/` 下有同名的 `StreamStream.swift` / `UnaryUnary.swift` / `StreamUnary.swift`(各 12 行,僅為 protocol 宣告)。本文所有行號**不**指向那些檔案。

### 2.1 所有權

**每一個非同步工作都應該有明確的擁有者,且它的失敗必須有人觀察。目前三個 task 全是孤兒。**

| Task | 位置 | 擁有者 | 失敗被觀察 |
|---|---|---|---|
| `runConnections()` | `StreamStream.swift:29` | 無 | **否 — 錯誤被吞** |
| RPC read loop | `…SpecifiedStream.Read.swift:64` | 僅由 completion 取消 | 是(有 catch) |
| events bridge | `Subscription.swift:77` | 無,且隱式強持有 `self` | 是 |

### 2.2 被吞掉的錯誤(hang 的關鍵)

```swift
// Sources/KurrentDB/Core/Additions/Usecase/StreamStream.swift:28-32
let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
Task {
    logger.debug("[\(Self.name)] Opening connection...")
    try await client.runConnections()   // ← 拋錯就此消失,無人持有、無人觀察
}
```

連線建立失敗時無人知曉 → RPC 永不拋錯(且無 deadline)→ `source` 永不終止 → teardown 永不觸發 → 靜默卡死。

`StreamStream` 是同目錄中唯一缺少 `defer { beginGracefulShutdown() }` 的路徑(`UnaryUnary.swift:44`、`StreamUnary.swift:38` 皆有)。

### 2.3 teardown 鏈鎖在 lazy getter 後

關閉連線需走完五段:

1. 存取 `.events` → 裝上 `continuation.onTermination`(`Subscription.swift:98`)← **唯一入口**
2. `tracker.callFinishActionOnce(...)`(`Subscription.swift:102`,全 repo 唯一呼叫點)
3. `onFinish` 註冊的 closure(`…Read.swift:90`)
4. `completion(error)`(`StreamStream.swift:36`)
5. `client.beginGracefulShutdown()`(`StreamStream.swift:43`)

`init`(`Subscription.swift:110-114`)沒有接上這條鏈,且全目錄無 `deinit`。

### 2.4 文件承諾了未實作的行為

`Subscription.swift:21-24` 的文件註解明載「letting the subscription go out of scope — automatically stops the underlying gRPC stream and closes the server-side connection」。此行為從未實作。因此加上 `deinit` 不是行為變更,而是履行既有合約。

### 2.5 `deinit` 無法單獨作為安全網(實測)

`Subscription.swift:77` 的 `Task {}` 無 capture list 卻引用 stored property,Swift 6 允許此處隱式 `self` 捕獲 → 該 Task 強持有整個 `Subscription`。

獨立最小範例實測(`swiftc -swift-version 6`):

```
CASE 1: 從未存取 .events 後丟棄   →  deinit 觸發
CASE 2: 存取 .events 後丟棄       →  deinit 永不觸發
```

實際發生的 hang 正是 CASE 2 的形態。故 `deinit` 只能作為輔助,不能作為主要機制。

## 3. 方案(A)

四處改動,全部落在已驗證的失效路徑上。

| # | 改動 | 位置 | 解決 |
|---|---|---|---|
| 1 | 持有 `connectionTask`,不再吞錯;completion 中額外 `.cancel()` | `StreamStream.perform` | **hang** |
| 2 | teardown 從 lazy getter 移入 `init` 的 `source.continuation.onTermination` | `Subscription.init` | teardown 不可達 |
| 3 | bridge Task 加明確 capture list,解除對 `self` 的強持有 | `Subscription.events` | 物件永不釋放 |
| 4 | 新增 `deinit` 作為「從未迭代就丟棄」的兜底 | `Subscription` | 連線洩漏 |

第 1 項是治 hang 的關鍵;2–4 治洩漏並履行文件合約。

**改動 1 的要求(明確化 — 本設計的核心不變式)**

連線 task 一旦結束 —— 無論正常返回或拋錯 —— 若該連線上的 RPC 仍在進行中,**必須使該 RPC 以錯誤終止,不得讓其無限等待**。

達成機制由實作計畫決定,但**不得**以「等待固定秒數後放棄」的方式滿足(理由見 §7)。

`callFinishActionOnce` 已具冪等性(`Subscription.swift:274`),重複觸發安全。

## 4. 錯誤語意

| 情境 | 拋出 |
|---|---|
| 連線 task 失敗 / 結束而 RPC 仍在等 | `.subscriptionDropped(reason:lastRevision:lastPosition:)` |
| RPC 本身被取消 | `.connectionClosed`(維持現狀) |

`subscriptionDropped` 與 `subscriptionTerminated` 已宣告於 `KurrentError.swift:58,60` 並有 description 處理,但**全 `Sources/` 從未拋出**。`subscriptionDropped` 攜帶的 `lastRevision` / `lastPosition` 正是 `tracker` 為斷線續傳而維護的資訊 —— 此 case 就是為本情境設計,只是從未接上。

重試錯誤分類沿用既有的 `KurrentError.isNodeFailure`(`KurrentError.swift:129`),不另訂。

## 5. 驗證

### 5.1 核心原則:斷言不碰時間

以「N 秒內沒卡住」斷言正確性,本身即是機率性測試 —— 等於用正在治療的病當藥。

Swift Testing 的 `.timeLimit` 經實測僅支援分鐘:

```
error: 'seconds' is unavailable: Time limit must be specified in minutes
```

故將兩件事切開:

| 目的 | 手段 | 數字由誰決定 |
|---|---|---|
| 斷言正確性 | 直接建構 `Subscription`,先同步驅動失敗再 await;實作正確時 stream 必定已終止 | **不涉及數字** |
| 偵測無限卡住 | suite `.timeLimit(.minutes(1))` + job `timeout-minutes` | 維運政策:「單元測試不該逼近一分鐘」 |

**誠實限制**:「永遠不會終止」在原理上無法不用時間界限偵測。此設計把界限推到維運層,而非讓它進入斷言。

### 5.2 契約測試(確定性,不需伺服器)

`Subscription.init(writer:)`、`send(state:)`、`onFinish(_:)` 均為 internal,測試可用 `@testable import KurrentDB` 直接建構驅動。`MockKurrentDBClient` 不適用 —— 它僅是 factory 呼叫的 spy,不模擬 gRPC 傳輸。

| # | 情境 | 斷言 |
|---|---|---|
| T1 | 建立後從未存取 `.events` 就丟棄 | teardown action 有執行(驗 `deinit` 兜底) |
| T2 | 迭代 `.events` 後 break 跳出 | teardown action 有執行 |
| T3 | RPC 拋錯 | `.events` 拋出且 teardown 執行 |
| T4 | 連線失敗 | `.events` 拋 `.subscriptionDropped`,同步驅動後再 await,不使用計時 |
| T5 | teardown 觸發兩次 | action 只執行一次(驗冪等) |

### 5.3 壓測(輔助,非驗收門檻)

於 Swift 6.0 環境迴圈跑 `PersistentSubscriptionAdvancedTests` 數十次;修前應能重現、修後不再發生。因屬機率性,提供信心但不作為驗收條件。

## 6. CI 護欄(獨立於 SDK 修正)

| 項目 | 理由 |
|---|---|
| `fail-fast: false` | 目前預設 `true`,一個 cell 失敗即取消其餘 15 個 → **主動銷毀診斷證據**,無法分辨單點問題與全面問題 |
| job `timeout-minutes` | 避免單一 job 佔用 16 分鐘 |
| suite `.timeLimit(.minutes(1))` | 維運上限 |

附帶:workflow 第 32 行 `- run: ulimit -n 10000` 為 no-op(每個 `run:` 是獨立 shell,不影響後續 `swift test` 步驟)。其存在本身即是過去曾撞過資源耗盡的證據。

## 7. 明確不做的事

| 項目 | 理由 |
|---|---|
| **SDK 加 RPC deadline** | 又是一個沒人能正當決定的數字。正確行為是「連線死掉時就失敗」,而非「等一個猜出來的時間後失敗」。改動 1 即為達成前者 |
| **改動 `UnaryUnary` / `StreamUnary` / `UnaryStream`** | 三者本就有 `defer`,且不在已驗證的失效路徑上。符合 Minimal Impact |
| **自動重連機制** | 見 §8 |

## 8. 未來範圍:自動重連

已討論但**刻意延後**。使用者的訴求為:持久訂閱斷線後,若 SDK 使用者未自行設計機制,將不再重連;希望提供自動重連並附開關參數。

**延後理由**:本修正是該功能的前提 —— 目前斷線根本不會被偵測,連「該重連了」的時機都不存在。核心穩定後再以獨立的一層 pattern 提供。

**已識別、屆時必須處理的問題**(記錄於此以免遺失):

1. `subscriptionId` 由伺服器 `.confirmation` 訊息提供(`Subscription.swift:118-119`),**每次重連都會變**。而 `ack(eventIds:)`(line 135)在呼叫當下才讀取它 → 重連後 ack 斷線前的事件會送往新 subscription。
2. teardown 會 `writer.stop()`,重連必須處理 writer 的重新綁定,否則 ack 靜默失效。
3. 持久訂閱為 at-least-once,重連本就會重送未 ack 事件 → 使用者會看到重複。若重連完全透明,使用者無從得知原因。
4. 可重用既有基礎設施:`OperationRetryPolicy`(`Core/RetryPolicy.swift:27`,含指數退避與 jitter)、`withRetry`(line 128)、`KurrentError.isNodeFailure`(line 129)。注意 `.default` 為 3 次嘗試,係為一次性操作設計,不適用於長生命週期訂閱。

**本設計不得阻擋該層** —— 改動 1 使連線死亡成為可觀察事件,正是重連所需的觸發點。

## 9. 證據強度

| 主張 | 強度 | 依據 |
|---|---|---|
| `StreamStream` 缺 defer、錯誤被吞 | 已驗證 | 直接讀原始碼 |
| teardown 鏈鎖在 lazy getter | 已驗證 | 唯一呼叫點 grep 確認 |
| bridge Task 強持有 self,`deinit` 不觸發 | 已驗證 | 獨立最小範例實測 |
| `.timeLimit` 僅支援分鐘 | 已驗證 | 編譯器錯誤訊息 |
| `subscriptionDropped` 從未被拋出 | 已驗證 | 全 `Sources/` grep |
| hang 源於連線錯誤被吞 | **高信心推論** | 程式碼結構充分,但 CI debug log 未開,未直接觀測 |
| SIGABRT 的確切 trap frame | **未知** | CI log 僅存 frame 27-28;SDK 路徑無 `fatalError`,abort 應在 NIO 層 |
| 「只有 Swift 6.0 有問題」 | **不可信** | `fail-fast` 造成系統性取樣偏差 |

**可提升證據等級的兩件事**:

1. CI 開啟 debug logging。若 hang 時 `"Closing connection..."` 確未出現,即可將 hang 機制升級為已證實。目前做不到 —— CI 僅有 info 級 log。
2. 以 `SWIFT_BACKTRACE=enable=yes,interactive=no` 重跑擷取完整 frame 0–26,可定位 SIGABRT。若套用修正後 hang 消失但 abort 仍在,則 abort 為獨立的第二個缺陷。
