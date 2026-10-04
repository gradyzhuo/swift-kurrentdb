# Scoped Read Delivery 與訂閱背壓 — 設計

日期：2026-10-04
來源：`SECURITY-AUDIT-2026-10-04.md` S02（無上限串流緩衝）
狀態：待審

## 1. 背景與目標

### 現況（已查證）

- `Streams.Read` / `Streams.ReadAll` 的 `send()` 在 `client.read { }` 內把整個回應 yield 進無上限 `AsyncThrowingStream`、`finish()` 後才 `return stream`。自 1.12.0（`125ccef6`，遷移 grpc-swift 2）起所有版本皆如此；1.11.x 以前是逐筆 pull。
- 這個設計換來一個保證：`send()` 回傳時 RPC 已結束、租約已歸還（#143 的 `BufferedStreamResponse` 依賴這點走共用連線）。代價是記憶體與結果大小成正比，`limit` 預設 `.max`。
- `Streams.Subscribe` / `SubscribeAll`：背景 `Task` 把 messages yield 進無上限 stream，`Subscription.init(messages:)` 再用 innerTask 轉進第二層無上限 `events` stream。消費者慢時兩層都無限累積。
- `Subscription.events` 是公開的 `AsyncThrowingStream<ReadEvent, Error>`。

### 目標

1. 提供一個讀取方式：**記憶體有上限**，且 **closure 結束時 RPC 一定已結束、租約一定已歸還**（保留原設計「讀完就確定關閉」的意圖）。
2. 訂閱改為有背壓，不再無上限累積。
3. 2.x 內完成，**不破壞任何公開 API**。

### 非目標

- 不改既有 `read()` 的行為（維持 buffered，**不加 `@available(deprecated)`**；文件改為推薦 scoped，是否 deprecate 留待 3.0 規劃時決定）。
- 不做分頁讀取（方案 D，見 §8）。
- 不處理 `PersistentSubscriptions.Read`、`Monitoring.Stats`、`Projections.Statistics`、`Users.Details`（見 §7）。
- 不處理 S08 `defaultDeadline`，但 §5 註明互動。

## 2. 設計原則：型別軸 vs options

本設計引入第一個「型別軸」。為避免日後濫用，訂下規則：

- **只有改變 API 形狀的設定才做成型別軸**：回傳型別不同、可用操作不同、生命週期／資源歸屬不同。
- **只改變值的設定留在 `inout` options closure**（`direction`、`limit`、`filter`、`resolveLinks`、credentials…）。型別軸是相乘的組合爆炸，options 是相加的。
- 一軸一語意，名稱描述語意（`delivery`、將來的 `version`），不用 `mode`／`policy` 這種空泛詞。
- 軸彼此正交；每一軸都有不帶參數的預設路徑，現有呼叫行為不變。
- 每個 constrained extension 提供完整 entry point（static dispatch，同 #143 的教訓）。
- 目前合格的軸只有兩個：本文的 `delivery`，與保留給伺服器協定的 `version`（v2 Read 出現時）。

## 3. 公開 API

```swift
let count = try await client.streams(specified: "orders")
    .delivery(.scoped)
    .read {
        $0.limit = 1000
    } body: { events in
        var count = 0
        for try await response in events { count += 1 }
        return count
    }
// body 返回或 throw → RPC 已取消／結束，租約已歸還
```

`$all` 同形：`client.allStreams.delivery(.scoped).read { ... } body: { ... }`。

### 命名

- **`delivery`**：回應「如何交付給呼叫端」。現有行為即「buffered」，是不呼叫 `delivery(_:)` 時的預設；2.x 只新增 `.scoped`，不公開 `.buffered` 值（YAGNI，3.0 若改預設再加）。
- 不用 `lifetime`：Swift 6.2 起 `@lifetime` 是 ~Escapable 的語言術語。
- 不用裸 `policy`：已有 `OperationRetryPolicy`，且 `policy:` 在呼叫點不傳達語意，也會吸引不相干設定塞進來。
- 不用 `strategy`：`ConsumerStrategy` 是 KurrentDB persistent subscription 的領域術語。
- 型別：`protocol ResponseDelivery`，`struct ScopedDelivery: ResponseDelivery`，`extension ResponseDelivery where Self == ScopedDelivery { static var scoped }`（同 swift-microsoft-graph `UsersTarget.v1` 的 static member 寫法）。

### 為什麼是 modifier 而不是 `streams(specified:delivery:)` 參數

- `KurrentDBClientProtocol` 是 public protocol，宣告了 `streams(specified:)` 等 requirement。新增 factory requirement 會讓使用者自己的 conformer（mock）編譯失敗；做成 protocol extension 又無法依 client 實作。
- `Streams` 是 concrete class，已有 `authenticated(_:)` 回傳新實例的 modifier 先例。`delivery(_:)` 加在 `Streams` 上，所有 client（含 mock 回傳的 `Streams`）自動獲得，不碰 protocol。
- `delivery(_:)` 與 `authenticated(_:)` 可任意順序串接。

### 型別

```swift
extension Streams {
    public func delivery(_ delivery: ScopedDelivery) -> ScopedStreams<Target>
}

public struct ScopedStreams<Target: StreamsTarget>: Sendable { /* wraps Streams<Target> */ }

extension ScopedStreams where Target == SpecifiedStream {
    public func read<R>(
        configure: @Sendable (inout Streams<SpecifiedStream>.Read.Options) -> Void = { _ in },
        isolation: isolated (any Actor)? = #isolation,
        body: (AsyncThrowingStream<Streams<SpecifiedStream>.Read.Response, any Error>) async throws -> R
    ) async throws -> R
}

extension ScopedStreams where Target == AllStreamsTarget {
    public func read<R>(/* 同上，ReadAll.Options / ReadAll.Response */) async throws -> R
}
```

- `ScopedStreams` 只提供 `read`。append／delete／subscribe 等不受 delivery 影響，不在此型別上（避免為一個軸複製整個 surface）。呼叫端要做其他操作就用原本的 `Streams`。
- `body` 非 `@Sendable`、在呼叫端 isolation 執行，`R` 不要求 `Sendable`。
- 錯誤型別用**無型別 `throws`**（偏離 SDK 慣用的 `throws(KurrentError)`）：`body` 是使用者程式碼，它拋出的錯誤原樣傳出，不包成 `KurrentError`。SDK 自身的 setup 錯誤仍是 `KurrentError`。
- 傳進 `body` 的 stream 若被逃逸到 closure 外，closure 結束後它只會讀到結束（handoff 已 finish），不會持有 RPC。

## 4. 內部元件

### 4.1 `ResponseHandoff<Element>`（package，`Sources/KurrentDB/Core/`）

單一生產者／單一消費者、固定小容量（初版 1，實作計畫可調）的交接通道。以 `Mutex` + `CheckedContinuation` 實作，不新增依賴。

- `send(_:) async throws`：緩衝滿時 suspend，直到消費端取走或通道終止；通道終止後 throw `CancellationError`。
- `next() async throws -> Element?`：有資料即回；無資料時 suspend；`finish` 後回 `nil` 或拋出錯誤。須 cancellation-aware（`withTaskCancellationHandler`），消費端取消時終止通道並喚醒生產者。
- `finish(throwing:)`：冪等。
- `makeStream() -> AsyncThrowingStream<Element, any Error>`：以 `AsyncThrowingStream(unfolding: { try await next() })` 包出，closure 捕捉一個 sentinel；sentinel `deinit` 時 `finish()` 並觸發 `onTermination` 回呼。（scratchpad probe 已確認：break 離開 scope、未迭代即丟棄、消費端 Task 取消三種情況 sentinel 都會 deinit；被變數持有時不會，與現行 `makeStream` 的 `onTermination` 語意相同。）

背壓鏈：消費端不拉 → `send` 卡住 → 不再迭代 `response.messages` → transport 不讀 → HTTP/2 flow-control window 滿 → 伺服器停送。

### 4.2 Scoped read 的執行路徑

新的 perform 路徑（constrained extension，不改 4 個 wire-shape protocol）：

```
perform(scoped:) 
  ├─ 選 node、檢查 serverInfo、acquire 共用租約          ← 可 retry（尚未呼叫 body）
  ├─ defer { lease.release() }
  └─ withThrowingTaskGroup
       ├─ child: client.read(request) { for msg in messages → handoff.send(handle(msg)) }
       │         結束時 handoff.finish(throwing:)
       └─ 本體: let r = try await body(handoff.makeStream())
                group.cancelAll()   ← body 返回或 throw 都會取消 child
                等 child 結束 → 回傳 r
```

- Structured concurrency 保證：`read(...)` 返回時 child 已結束，即 RPC 已結束；`defer` 保證租約已歸還。這是本設計對原始意圖（讀完確定關閉）的保證來源。
- 使用共用連線租約（與 #143 相同的 `acquire`），中止靠取消 child task，**不關連線**。
- **Retry**：只涵蓋呼叫 `body` 之前（選 node、unsupported、建立 request、租約）。`body` 開始後不 retry，否則 body 會重複處理事件。
- `Read`／`ReadAll` usecase 本身不變，繼續 conform `BufferedStreamResponse` 供舊 `read()` 使用；scoped 路徑另寫一個只取 `handle(message:)` 與 `request(metadata:)` 的 send 變體。

### 4.3 訂閱背壓

- `Streams.Subscribe` / `SubscribeAll` 的 `send()`：背景 Task 改為 `handoff.send(message)`，取代無上限 `yield`。
- `Subscription.init(messages:)`：先讀 confirmation（不變），之後 `events` 改為 `AsyncThrowingStream(unfolding:)`，直接從 handoff 拉訊息、過濾非 event、轉成 `ReadEvent`；拿掉 innerTask 與第二層 stream。
- `events` 的 sentinel 終止時 → finish handoff → 觸發既有 completion → `connection.close()`（訂閱繼續用獨立連線，不改連線策略）。
- `Subscription.cancel()` 改為終止 handoff。`continuation`、`task` 是 `package` 欄位，可改；`events`、`subscriptionId`、`cancel()` 公開介面不變。
- 生命週期維持現狀：仍由呼叫端 `cancel()` 或釋放 `events` 結束。本設計只移除無上限緩衝。

## 5. 錯誤與邊界

- 伺服器在接受呼叫前就拒絕（只回 status，例如 unauthenticated / access denied / unavailable），或連線失敗：由 `read(...)` 在 `body` 執行前以 `KurrentError` 拋出，並依 retry policy 重試。呼叫被接受之後的錯誤（包含以 response message 形式到達的 stream-not-found）在 `body` 迭代 stream 時浮現，與現行 `read()` 一致。
- Setup 錯誤（unsupported feature、metadata、租約失敗）由 `read(...)` 直接拋出，`body` 不會被呼叫。
- `body` 內卡住不迭代：背壓讓伺服器停送，但 RPC 仍持有到 body 返回。這是呼叫端程式的責任；S08 修好 `defaultDeadline` 後可由 deadline 收掉。spec 在 API 文件註明。
- 消費端提早 `break`：body 繼續執行到返回為止，返回時 child 被取消。
- 伺服器端 `$all` filtered read 的 checkpoint 等非 event 回應，照現行 `Response` 型別交付，不過濾。

## 6. 測試

**單元（`MockClientTests` 或新 target，離線）**
- `ResponseHandoff`：生產者最多領先消費者「容量」筆；消費端取消 → 生產者 `send` throw；`finish(throwing:)` 傳遞錯誤；sentinel deinit（break、丟棄、取消）→ `onTermination` 觸發。
- Scoped 路徑：body 返回／throw 後 child task 已結束（以 fake send 驗證）；body 開始後的錯誤不 retry。

**Live（需 cluster）**
- Scoped read：大 stream 只取第一筆即 break → `read(...)` 返回後租約已歸還（`ConnectionProvider` retainCount 回到原值），已產生筆數 ≤ 已消費 + 容量。
- Scoped read 與舊 `read()` 讀同一 stream 結果相同。
- 同一共用連線上，取消一個 scoped read 不影響並行中的其他 RPC（驗證取消只 reset 單一 HTTP/2 stream）。**這是實作計畫第一步；不成立則 scoped 路徑改用獨立連線。**
- 慢消費者訂閱：寫入大量事件，消費端延遲 → 用戶端未消費的緩衝筆數有上限。

**文件**
- DocC 與 README 範例走 `scripts/check-doc-snippets.sh` 編譯。

## 7. 範圍外 / 後續

- `PersistentSubscriptions.Read`、`Monitoring.Stats`：同樣的無上限 Task 寫法，之後可共用 `ResponseHandoff`。
- `Projections.Statistics`、`Users.Details`：回應小，維持 buffered。
- 舊 `read()` 的去留：2.x 不 deprecate，只在文件推薦 `delivery(.scoped)`；3.0 是否 deprecate 或讓 scoped 成為預設 `read`，另案決定。
- `version` 軸：待伺服器提供 v2 Read RPC 時依 §2 原則新增。

## 8. 曾考慮的方案

- **A：交出 lazy stream**（`unfolding` + handoff + sentinel）：有背壓、不破壞 API，但連線何時關取決於呼叫端（被持有、逃逸、迴圈本體卡住都關不掉），違背原始意圖。只採用於訂閱（訂閱本來就是交出 stream）。
- **B：自訂公開 `AsyncSequence` 型別**：破壞 API，只能 3.0。
- **D：分頁讀取**：舊 API 不變且每個 RPC 確定關閉，但需處理跨頁 `limit`、`$all` position 接續是否 inclusive、filter checkpoint；為將被 deprecated 的 API 不划算。
- **`streams(specified:version: .v2)`**：`v2` 已是伺服器協定版本（`AppendSession`/`AppendRecords`），語意衝突；改用 `delivery` 軸。
- **`streams(specified:delivery:)` factory 參數**：需改 public `KurrentDBClientProtocol`；改用 modifier。
