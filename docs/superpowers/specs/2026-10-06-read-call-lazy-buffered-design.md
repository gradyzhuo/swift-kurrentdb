# `ReadCall`：`.lazy` / `.buffered` 讀取與訂閱背壓 — 設計

日期：2026-10-06
基準：`origin/main` `907ddf55`
來源：`SECURITY-AUDIT-2026-10-04.md` S02（無上限串流緩衝）；3.0 決定見 `docs/adr/0001-read-becomes-lazy-in-3-0.md`
狀態：待審

這份 spec 是最終設計的乾淨版，不含先前討論過程。先前在 `feat/scoped-read-delivery`（PR #148）上的實作只作為 reviewer 的邊角案例對照，不作為本次實作的來源。

## 1. 背景與目標

### 現況（已查證）

- `Streams.Read` / `Streams.ReadAll` 的 `send()` 在 gRPC 的 `client.read { }` 回應 closure 內把整個回應 yield 進一條無上限 `AsyncThrowingStream`，`finish()` 後才 `return stream`。自 1.12.0（`125ccef6`，遷移 grpc-swift 2）起皆如此；1.11.x 以前是逐筆 pull。
- 這個設計的保證：`read()` 回傳時 RPC 已結束、共用連線租約已歸還（#143 的 `BufferedStreamResponse` 依賴這點走共用連線）。代價：記憶體與結果大小成正比，`limit` 預設 `.max`。
- `Streams.Subscribe` / `SubscribeAll`：背景 `Task` 把 messages yield 進無上限 stream，`Subscription.init(messages:)` 再用一個 innerTask 轉進第二層無上限 `events` stream。消費者慢時兩層都無限累積。
- `Streams<Target>.ReadResponse` 是巢狀在泛型 `Streams` 內的 `public enum ReadResponse: Sendable`，`Read.Response` 與 `ReadAll.Response` 都是它。
- grpc-swift 2 的 `client.read(request:) { response in … }`：closure 一結束 RPC 就結束；要逐筆交付就得留在 closure 內。

### 目標

1. 提供一種讀法：記憶體有上限（交接通道：一個已緩衝元素加上被暫停的 producer 手上持有的一個元素；傳輸層 `NIOAsyncChannel` 的 inbound 訊息佇列，grpc-swift-nio-transport 預設 high watermark 為 10 則完整訊息；以及一個 HTTP/2 stream flow-control window，預設約 8 MiB），不與結果大小成正比；不宣稱測試未量測的位元組上限，且**迭代結束（跑完、`break`、`throw`、呼叫端 Task 取消）RPC 就關閉、租約就歸還**。
2. 訂閱改為有背壓，不再無上限累積。
3. 2.x 內完成，**不改變任何既有公開符號的簽名或行為、不 deprecate**；既有的呼叫（`try await read()`、`read { … }`、`for try await … in read()`、`.reduce` 等）一字不改、語意不變。**明文接受的唯一例外**（2026-10-06 決定，見 §6）：在同步 context 把 `stream.read` 當函式值存起來的寫法，其型別會改為 `ReadCall` factory——這在實務上極少見，且後果是編譯錯誤而非靜默改變；不為它另設入口名稱。
4. 為 3.0「`read()` 預設 lazy」鋪路（ADR 0001）。

### 非目標

- 不改既有 `read(configure:) -> AsyncThrowingStream` 的行為或簽名，不加 `@available(deprecated)`。
- 不提供 closure-scoped 的讀取形式（`withEvents`、`process`、`read { events in }`）。
- 不處理 `PersistentSubscriptions.Read`、`Monitoring.Stats`（同樣的無上限寫法，列為後續）、`Projections.Statistics`、`Users.Details`（回應小，維持 buffered）。
- 不處理 S08 `defaultDeadline`。

## 2. 公開 API

```swift
// 既有，不變：整批先抓回來，RPC 在 return 前結束。文件說明它等同 read().buffered。
for try await response in try await client.streams(specified: "orders").read { $0.limit = 10 } { … }

// 新增：read(configure:) -> Streams<Target>.ReadCall（sync、cold，不做任何網路動作）
for try await response in client.streams(specified: "orders").read().lazy { … }
for try await response in try await client.allStreams.read().buffered { … }

let total = try await client.streams(specified: "orders")
    .read { $0.limit = 10_000 }
    .lazy
    .reduce(0) { $0 + amount($1) }

let first = try await client.allStreams.read().lazy.first { try $0.event.record.eventType == "OrderCancelled" }
```

### 2.1 `Streams<Target>.ReadCall`

- `public struct ReadCall: Sendable`，巢狀在 `Streams`（和 `Streams.Subscription` 同一層級；`ReadResponse` 本身就巢狀在泛型 `Streams` 內，所以 `ReadCall` 不能是頂層非泛型型別）。
- 由 `Streams where Target: SpecifiedStreamTarget` 與 `Streams where Target == AllStreamsTarget` 各提供一個 overload：
  ```swift
  public func read(configure: @Sendable (inout Read.Options) -> Void = { _ in }) -> ReadCall
  public func read(configure: @Sendable (inout ReadAll.Options) -> Void = { _ in }) -> ReadCall   // $all
  ```
  **硬規定：這兩個 overload 必須是 sync、non-throwing**（見 §6）。
- 內部持有 target、已 configure 的 options、`selector`、`callOptions`、`overrideCredentials`。`authenticated(_:)` 照舊在 `Streams` 上，所以 `client.streams(specified:).authenticated(creds).read().lazy` 直接成立。
- **2.x 不實作 `AsyncSequence`**（見 §6）。
- 只有兩個成員：`lazy`、`buffered`。

### 2.2 `ReadCall.lazy`

```swift
public var lazy: Lazy { get }                       // sync
public struct Lazy: AsyncSequence, Sendable {
    public typealias Element = ReadResponse
    public typealias Failure = any Error
    public func makeAsyncIterator() -> Iterator
    public final class Iterator: AsyncIteratorProtocol { public func next() async throws -> ReadResponse? }
}
```

- 每次 `makeAsyncIterator()` 代表一條新的 RPC；sequence 本身是冷的、可重複迭代。
- 記憶體上限（每條 lazy read）：交接通道（一個已緩衝元素 + 被暫停 producer 持有的一個元素）、傳輸層 inbound 訊息佇列（預設 10 則訊息）、一個 HTTP/2 stream flow-control window（預設約 8 MiB）；不與結果大小成正比，不宣稱測試未量測的位元組上限。
- `Iterator` 是 reference type。第一次 `next()`：`Task.checkCancellation()` → `withRetry(policy:) { node in open(node) }`（選節點、檢查 `serverInfo.isSupported`、`acquire` 共用租約、建 request、起 Task 跑 `client.read`、等伺服器接受）→ 取得 `ScopedCall`。之後每次 `next()` 就是 `handoff.next()`。
- 退場（§4.3）：iterator `deinit` 時 `handoff.cancel()`、`task.cancel()`，並以一個 unstructured `Task` 執行 `await task.value; lease.release()`（deinit 不能 await）。所以迴圈跑完、`break`、`throw`、呼叫端 Task 取消都會關 RPC。唯一守不住的情況：呼叫端手動 `makeAsyncIterator()` 後把 iterator 存起來——文件註明。
- 取消：呼叫端 Task 被取消時 `next()` 拋 `CancellationError`（不是安靜回 `nil`），不論取消發生在選節點、等接受、或迭代中。
- 錯誤：伺服器接受前的拒絕（status-only：unauthenticated、access denied、unavailable）與連線失敗，在第一次 `next()` 拋出為 `KurrentError`，`isNodeFailure` 者依 `OperationRetryPolicy` 重試（此時尚未交付任何元素，重試不會重複交付）；接受後的錯誤（含 stream-not-found，它是 response message）在迭代中拋出，和既有 `read()` 一樣。拋錯一次之後 `next()` 回 `nil`（AsyncSequence 慣例）。
- 連線：走共用 HTTP/2 連線的租約（`ConnectionProvider.acquire`）。取消 iterator 只 reset 自己那條 HTTP/2 stream，不影響同連線上的其他 RPC——這點必須先以 live spike 證明（§7 Task 1），不成立則 `.lazy` 改用 `openDedicated`。

### 2.3 `ReadCall.buffered`

```swift
public var buffered: AsyncThrowingStream<ReadResponse, any Error> { get async throws }
```

- 就是既有 `read()` 的實作（`Read` / `ReadAll` usecase 的 `perform(selector:callOptions:credentials:)`，`BufferedStreamResponse` 共用連線路徑），原封不動。
- `try await` 落在這個屬性上，誠實表達「這一步會先把全部資料抓完」。回傳時 RPC 已結束、租約已歸還。
- 既有 `read(configure:) async throws -> AsyncThrowingStream` 內部可直接改寫為 `read(configure:).buffered`，或兩者共用同一個 package helper；對外行為完全相同。

### 2.4 訂閱

`Subscription.events`、`subscriptionId`、`cancel()` 的簽名不變；只有 `package` 成員改變（§4.4）。行為差異：消費端慢時不再無限累積，伺服器會被 HTTP/2 flow control 暫停。這點要寫進 release notes。

## 3. 命名

- `ReadCall`：2.x 讀作「一個還沒執行的 read 呼叫，`.lazy` / `.buffered` 決定怎麼執行」；3.0 若實作 `AsyncSequence`，讀作「迭代也會執行它」。`Read` 已是 usecase 名稱，不可用。
- `.lazy` / `.buffered`：對比明確。`lazy` 在 Swift 既有語意是「延後 map/filter」，這裡是「延後拉資料」，精神一致；`AsyncSequence` 沒有 `.lazy` 成員，不撞 API。
- 不提供 `withEvents` / `process`：`read().lazy.reduce` 與之等價，差別只在租約歸還是 iterator deinit 內非同步完成，而非 return 前 await 完成。
- `ReadCall.Lazy` / `ReadCall.Lazy.Iterator`：巢狀型別，使用者幾乎不會拼出來。

## 4. 內部元件

### 4.1 `ResponseHandoff<Element>`（package，`Sources/KurrentDB/Core/ResponseHandoff.swift`）

單一 producer / 單一 consumer、固定容量（預設 1）的交接通道，`Mutex` + `CheckedContinuation` 實作，不新增依賴。

- `init(capacity: Int = 1, onTermination: @escaping @Sendable ((any Error)?) -> Void = { _ in })`，`precondition(capacity >= 1)`。
- `send(_:) async throws`：滿則 suspend；通道終止後 throw `CancellationError`。**producer 的 Task 在 `send` 中被取消只喚醒 producer**：suspended 的 `send` 以 `CancellationError` 返回，之後的 `send` 立即拋 `CancellationError`（記錄 `producerCancelled`），但**通道保持開啟、不設 terminal**；終結錯誤由 producer 的擁有者以 `finish(throwing:)` / `finish()` 決定，或由 consumer 取消。原因：grpc-swift 以取消 response handler 的 Task 來執行 RPC deadline，若在此直接以 `CancellationError` 終結，之後擁有者帶來的真正錯誤（`RPCError.deadlineExceeded`）會因冪等而被丟棄，閒置的 `.lazy` / 訂閱消費者就會把逾時當成取消；RPC 自己的最終錯誤必須贏過 grpc-swift 用來強制 deadline 的 Task 取消。
- **與 grpc-swift 版本無關的 deadline 對應**：擁有者（`open()` 與訂閱的 `send()`）把「非自己要求的」`CancellationError`（`Task.isCancelled == false`；我們自己的 `close()` 會取消 Task）對應成 `RPCError(.deadlineExceeded)`，handler 另以 `HandlerCancellation` 旗標記錄「看過取消」，使 `call(...)` 正常返回但 handler 曾被取消時也對應成 deadlineExceeded。原因：Swift 6.0 解析到較舊的 grpc-swift（2.3.0），其 `withDeadline` 不會改拋 deadlineExceeded，而是原樣回傳 handler 的結果（`CancellationError` 或正常結束）；新版才會在取消並等待 handler 後 rethrow `RPCError(.deadlineExceeded)`。
- `next() async throws -> Element?`：空則 suspend；須 cancellation-aware（`withTaskCancellationHandler`），consumer Task 取消 → `cancel()`。`precondition(state.consumer == nil)`：單一 consumer。
- `finish(throwing:)`（producer 側，冪等）：設 terminal；喚醒等待中的 consumer；**也喚醒 pending 的 producer（以 `CancellationError`）**，其元素丟棄不計數；`onTermination(error)` 一次。consumer 先排空 buffer 再收到 `nil` / error；error 只拋一次，之後 `nil`。
- `cancel()`（consumer 側，冪等）：
  - terminal 為 nil：設 `.cancelled`、清 buffer、consumer resume `nil`、pending producer resume `CancellationError`、`onTermination(nil)` 一次。
  - **terminal 已是 `.finished`**：仍清 buffer、丟棄待交付 error、切到 `.cancelled`，但不再觸發 `onTermination`。（否則 producer 先結束、iterator 後釋放時，殘留 buffer 會繼續交付。）
- `makeStream(_ transform: @escaping @Sendable (Element) throws -> T?) -> AsyncThrowingStream<T, any Error>`（`nil` 跳過）與 `makeStream()`：以 `AsyncThrowingStream(unfolding:)` 包出，closure 捕捉一個 sentinel，sentinel `deinit` → `cancel()`。**transform 或 `next()` 拋錯時，closure 內 catch → `cancel()` → rethrow**（`unfolding` stream 拋錯後不會釋放 closure，不補這一步會讓 handoff 和連線活到 stream 被釋放為止）。訂閱用；`.lazy` 不用（它自己有 iterator）。
- 計數：`sentCount`、`deliveredCount`、`capacity`，供測試驗證背壓。
- 所有 continuation 在鎖外 resume；`onTermination` 恰好一次（finish / cancel 先到者）。

### 4.2 `ScopedStreamResponse`、`AcceptanceGate`、`ScopedCall`、`open(node:)`

- `package protocol ScopedStreamResponse: UnaryStream, BufferedStreamResponse`（`GRPCEncapsulates/ResponseHandlable.swift`），要求 `call<Result: Sendable>(connection:request:callOptions:onResponse:)`：呼叫 generated client 的 `read(request:options:onResponse:)` 並原樣轉傳 `onResponse`。`Streams.Read`、`Streams.ReadAll` 遵守。4 個 wire-shape protocol 不動。
- `AcceptanceGate`（private）：一次性 open / fail 信號，`wait()` cancellation-aware，continuation 恰好 resume 一次。
- `package final class ScopedCall<Response>`：持有 `handoff`、`lease: SharedLease`、`task: Task<Void, Never>`。`close() async`：`handoff.cancel()` → `task.cancel()` → `await task.value` → `lease.release()`（順序不可變：先 consumer 側終止，退場才是安靜的）。另提供給 iterator deinit 用的非 await 版本（`cancel()` + 背景 Task 收尾）。
- `open(node:callOptions:credentials:) async throws(KurrentError) -> ScopedCall<Response>`（`UnaryStream+Scoped.swift`，extension on `ScopedStreamResponse where Transport == HTTP2ClientTransport.Posix`）：`isSupported` 檢查 → `acquire` 租約 → 建 request（失敗則 release） → 起 Task 跑 `call(...)`：`response.accepted` 成功則 `gate.open()` 後 `for try await message in response.messages { try await handoff.send(handle(message)) }`，結束 `finish()`；handler 內不 catch：`send` / `handle` / `messages` 拋出的錯誤傳出 handler，由外層 `do/catch` 在 `call(...)` 最終拋出什麼就 `finish(throwing:)` 什麼（deadline 時為 `RPCError.deadlineExceeded`），`call(...)` 正常返回後再 `finish()` 一次（冪等的保險）；失敗則 `gate.fail(error)` → 等 `gate.wait()`，失敗則 `close()` 後拋出。呼叫端在等待接受時被取消 → 映成 `KurrentError.connectionClosed`（typed throws 限制；`withRetry` 不重試它），由 iterator 層再轉成 `CancellationError`。
- `.lazy` 的 iterator 第一次 `next()` 走 `withRetry { open }`；setup 任一階段若 `Task.isCancelled` 一律拋 `CancellationError`（節點探索會把取消包成 `internalClientError`，不能只認 `connectionClosed`）。

### 4.3 `.lazy` iterator 的生命週期

```
first next():  checkCancellation → withRetry { select node → open(node) } → call
each next():   call.handoff.next()  （nil → 結束；取消 → CancellationError）
deinit:        call.handoff.cancel(); call.task.cancel(); Task { await call.task.value; call.lease.release() }
```

- 租約歸還是非同步的；測試用 `eventually { retainCount == 0 }`。
- 收到 `nil`（正常結束）或拋錯後，iterator 可立即主動 close（不必等 deinit），讓租約儘早歸還。

### 4.4 訂閱背壓

- `Subscribe` / `SubscribeAll` 的 `send()`：背景 Task 改為 `try await handoff.send(message)`；`completion`（關獨立連線）作為 `onTermination`。
- `Subscription.init(messages:)`：先用 `next()` 讀 confirmation（失敗 → `cancel()` 後 throw）；`events = handoff.makeStream { .event → ReadEvent; caughtUp / 其他 → nil（保留現有 debug log）}`；拿掉 innerTask 與第二層 stream。
- `Subscription` 的 `package` 成員：`messages: ResponseHandoff<Read.UnderlyingResponse>` 取代 `continuation` / `task`；`cancel()` → `messages.cancel()`。
- 訂閱繼續用獨立連線（長時間佔住 HTTP/2 stream 不適合共用）。

## 5. 錯誤與取消對照

| 情境 | `read()` / `.buffered` | `.lazy` |
|---|---|---|
| 接受前被拒（status-only）、連線失敗 | `read()` / `buffered` 拋 `KurrentError`，node failure 重試 | 第一次 `next()` 拋 `KurrentError`，node failure 重試 |
| 接受後的錯誤（stream-not-found、deleted） | 迭代時拋 | 迭代時拋，之後 `nil` |
| 呼叫端 Task 取消 | 依既有行為 | `next()` 拋 `CancellationError` |
| 中途 `break` | stream 留著直到釋放（RPC 早已結束） | iterator 釋放 → RPC 關、租約（非同步）歸還 |
| 存起來不迭代 | 無 RPC 可佔 | sequence 無害；iterator 若被存起來則 RPC 持續佔用 |
| 迭代中 body 卡在別的 await | — | RPC 持續開啟，伺服器被背壓暫停 |
| 記憶體 | ∝ 結果大小 | 有界：交接通道（1 個緩衝 + 1 個被暫停 producer 持有）+ 傳輸層 inbound 佇列（預設 10 則訊息）+ 一個 HTTP/2 stream window（預設約 8 MiB）；不與結果大小成正比 |

## 6. Overload 解析的硬規定與已知限制

兩個 `read(configure:)` 只差回傳型別。compile probe（Swift 6.4）結論：

- 若兩者 effects 相同（都 `async throws`），所有沒寫型別的呼叫點（`for try await r in read()`、`let s = read()`、`read().reduce`）皆 ambiguous。
- 若新 overload 為 **sync、non-throwing**、且 `ReadCall` **不是 `AsyncSequence`**：既有呼叫（一律帶 `try await`）全部解析到舊 overload；`.lazy` / `.buffered` 鏈（成員只有 `ReadCall` 有）解析到新 overload。無歧義。兩個條件缺一不可，是 2.x 的硬規定，須在 `ReadCall` 的文件註解寫明。
- 沒有型別標註的 function reference `stream.read`：在 async context 中形成時仍綁定 buffered overload；在同步 context 中形成時綁定 `ReadCall` overload，需要時請明寫型別。`@_disfavoredOverload` 對此沒有影響（已驗證），因此不使用。**這是刻意接受的 2.x source change**（外部 review 第二輪指出；決定：接受並記錄，而非為 factory 另取名字）：任何與既有 `read` 同名的新 overload 都會改變裸 `stream.read` 參照在某些 context 下的意義，唯一能完全避免的方法是不同的名字，而保留 `read` 的價值高於這個罕見寫法。release notes 要寫明。
- 已知限制：`let call = stream.read()`（不加 `try await`、不接成員）解析到舊 overload 並因缺 `try await` 報錯；要單獨持有需寫 `let call: Streams<SpecifiedStream>.ReadCall = stream.read()`。3.0 移除舊 overload 後消失。
- `for try await r in stream.read { … }.buffered { … }` 觸發 Swift 的 trailing-closure-confusable 警告；文件示範 `read(configure: { … })` 或先存變數。
- 以上四點要有編譯層級的測試（offline target 內實際寫出這些呼叫並斷言型別），避免日後有人把新 overload 改成 async 而不自知。

## 7. 測試

**Task 1 spike（live）**：在共用租約上開一條 Subscribe 作為「不會結束的 RPC」，等它收到第一筆事件後，於同一連線上跑完整的 buffered read；取消前者；再跑一次 read；斷言兩次都讀到全部事件、`createdSharedConnectionCount` 未增加、前者以 cancellation 結束。不成立則 `.lazy` 改用獨立連線。

**離線（`Tests/MockClientTests`）**
- `ResponseHandoffTests`：順序交付；`finish(throwing:)` 排空後拋一次再 `nil`；producer 最多領先容量筆（用 poll-until，不用固定 yield 次數）；`cancel()` 喚醒 suspended producer 且 `onTermination` 一次；finish 後 cancel 不再觸發 `onTermination` **且丟棄 buffer 與待交付 error**；未迭代即丟棄的 stream 會 cancel；break 後釋放會 cancel；consumer Task 取消會 cancel 且 consumer 以 success 結束；producer Task 取消 → producer 以 `CancellationError` 返回但通道仍開啟，擁有者 `finish(throwing:)` 後 consumer 排空再收到該錯誤、`onTermination` 一次；取消後再 `send` 立即拋 `CancellationError`；`finish` 喚醒 pending producer；suspended consumer 收到 `finish(throwing:)` 的 error；transform throw → handoff 被 cancel、後續 `send` 拋 `CancellationError`、`next()` 回 `nil`。
- `LazyReadPathTests`（127.0.0.1:1 拒絕連線 + NIO `ServerBootstrap` silent listener）：拒絕連線 → 第一次 `next()` 拋 `KurrentError`、走共用路徑（`createdSharedConnectionCount == 1`、dedicated 0）、`retainCount` 最終 0；unsupported method → `.unsupportedFeature`、不取租約；等接受時取消（silent listener、無 timeout）→ `CancellationError`、retainCount 0；未快取節點、預先取消 → `CancellationError`；探索中取消 → `CancellationError`；iterator 被丟棄（未 `next()`）不留任何租約。
- 既有 `UnaryStreamConnectionPathTests`：證明 `read()` / `.buffered` 仍走 buffered 共用路徑。
- Overload 解析的編譯測試（§6）。

**Live（`Tests/StreamsTests`，3 節點 TLS cluster）**
- `LazyReadLiveTests`：短 deadline（1s）+ 閒置消費者 → `.lazy` 與訂閱收到 `RPCError.deadlineExceeded` 而非 `CancellationError`；`.lazy` 與 `read()` / `.buffered` 讀同一 stream 結果相同；只取第一筆就 `break` → `eventually(retainCount == 0)`，且 `sentCount - deliveredCount <= capacity`、`sentCount < 總筆數`（背壓）；迭代中 `break` 前 `retainCount == 1`（正向對照）；呼叫端 Task 取消（第一筆到達後再取消，用 signal 不用固定 sleep）→ `CancellationError`、retainCount 0；不存在的 stream → `.lazy` 與 `read()` 錯誤描述一致，且錯誤在迭代中浮現；`$all` `.lazy` 配 `limit`；錯誤帳密 → 第一次 `next()` 前拋 `KurrentError`；`shutdown()` 後 `.lazy` 第一次 `next()` 拋 `.connectionClosed`；同一共用連線上取消一條 `.lazy` 不影響並行的 read（Task 1 spike 的 API 層版本）。
- `SubscriptionBackpressureLiveTests`：慢消費者 → `sentCount - deliveredCount <= capacity` 且 `sentCount < N`（先 append N 筆、從 `.start` 訂閱）；`cancel()` 於消費端等待時 → 迴圈正常結束、獨立連線 `eventually` 歸零；`$all` 版本同樣有真實上限斷言。
- 既有 `StreamsTests`、`AllStreamsTargetTests`、`ConnectionReuseLiveTests` 不改（它們測的是 `read()`，行為不變）。

**可攜性**：新測試碼要在 Swift 6.0 編譯（Docker `swift:6.0-jammy` 對乾淨 worktree `swift build --build-tests`）；CI 矩陣 6.0–6.4 全綠。注意 `AsyncIteratorProtocol` 在 6.0 的 `next()` 簽名（可選實作 `next(isolation:)`）。

**文件**：`scripts/check-doc-snippets.sh` exit 0。

## 8. 文件

- DocC《Reading events》：維持以 `for try await … in try await read()` 為主；新增「Bounded memory: `.lazy`」一節（用途、iterator 釋放即關閉、唯一守不住的情況、`first` / `prefix` / `reduce` 範例）、「`.buffered`」一句話（等同 `read()`）、「Roadmap」一段指向 ADR 0001（3.0 預設 lazy）。訂閱背壓一句話。
- README：在 read 範例旁加一行 `.lazy` 入口。
- `///`：`ReadCall`（含 §6 硬規定）、`lazy`、`buffered`、既有 `read()` 加一句「等同 `read().buffered`；大量讀取見 `.lazy`」。
- `CHANGELOG` / release notes 草稿：新增 `.lazy`、訂閱背壓的行為變化、無 breaking change。

## 9. 否決紀錄（簡）

`.delivery(.scoped)` 型別軸、`read(.lazy)` / `read(loading:)` marker、`read { events in }` closure overload（+ 短暫 deprecate `read()`）、`withEvents` / `processWithEvents`、`read().delivery(.buffered).withEvents`、per-event callback `read { event in }`、只提供 closure 形式、`AsyncThrowingStream` 內部改 lazy。理由見 ADR 0001「Alternatives considered」與 PR #148 的討論紀錄。
