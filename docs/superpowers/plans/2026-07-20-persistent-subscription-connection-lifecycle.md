# 持久訂閱連線生命週期修正 — 實作計畫

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 讓持久訂閱的 gRPC 連線有明確的擁有者,使連線死亡成為可觀察事件,消除 CI 上偶發的靜默 hang 與資源洩漏。

**Architecture:** 目前三個非結構化 Task 皆無擁有者,且 teardown 鏈的唯一入口鎖在 lazy computed property 後。本計畫將 teardown 提前至 `init` 佈署、解除 bridge Task 對 `self` 的強持有、為 `StreamStream.perform` 的連線 Task 建立擁有權與取消路徑,並補上 `deinit` 兜底。

**Tech Stack:** Swift 6、grpc-swift 2.x(`GRPCCore` / `GRPCNIOTransportHTTP2Posix`)、Swift Testing、`Synchronization.Mutex`

**Spec:** `docs/superpowers/specs/2026-07-20-persistent-subscription-connection-lifecycle-design.md`

## Global Constraints

- Swift 6.0 以上,完整 data-race safety;新增型別須為 `Sendable`
- 不得新增 RPC deadline 或任何「等待固定秒數後放棄」的邏輯(spec §7)
- 不得修改 `UnaryUnary` / `StreamUnary` / `UnaryStream`(spec §7)
- 測試斷言不得依賴牆鐘時間;時間界限僅可存在於 suite `.timeLimit` 與 job `timeout-minutes`(spec §5.1)
- `.timeLimit` 僅接受分鐘(`.seconds` 為 unavailable)
- commit message 不得含 `Co-Authored-By`(CLAUDE.local.md)
- 分支:`fix/persistent-subscription-connection-lifecycle`(已建立,基於 `origin/main`)

## 檔案路徑對照(同名檔案不只一份,務必開對)

| 簡寫 | 實際路徑 |
|---|---|
| `StreamStream.swift` | `Sources/KurrentDB/Core/Additions/Usecase/StreamStream.swift`(46 行) |
| `Subscription.swift` | `Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.Subscription.swift`(283 行) |
| `Read.swift` | `Sources/KurrentDB/PersistentSubscriptions/Usecase/Specified/PersistentSubscriptions.SpecifiedStream.Read.swift` |
| `AllStream.Read.swift` | `Sources/KurrentDB/PersistentSubscriptions/Usecase/AllStream/PersistentSubscriptions.AllStream.Read.swift` |
| `KurrentError.swift` | `Sources/KurrentDB/Core/Error/KurrentError.swift`(299 行) |

**易錯**:`Sources/GRPCEncapsulates/Usecase/` 下有同名的 `StreamStream.swift`(12 行,僅 protocol)。本計畫行號**不**指向該檔。

## File Structure

| 檔案 | 動作 | 責任 |
|---|---|---|
| `Tests/KurrentCoreTests/GRPCClientLifecycleCharacterizationTests.swift` | 建立 | 釘住 grpc-swift 2 的實際行為(Task 1) |
| `Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift` | 建立 | 生命週期契約測試 T1–T5 |
| `Subscription.swift` | 修改 | teardown 佈署時機、capture list、`deinit` |
| `StreamStream.swift` | 修改 | 連線 Task 擁有權與取消 |
| `.github/workflows/swift-build-testing.yml` | 修改 | CI 護欄 |

---

## Task 1: 特性化測試 — 釘住 grpc-swift 的實際行為

**為什麼這是第一個任務**:spec §9 將「hang 源於連線錯誤被吞」列為**高信心推論而非已驗證**。而 `GRPCClient.swift:219-222` 的 `defer { state.stopped() }` 顯示,即使錯誤被吞,Task 結束時 client 仍會 stopped——進行中的 RPC 理應失敗。若真如此,吞錯就不是 hang 的唯一成因。**在推論被釘成事實之前不得改動生產程式碼。**

**Files:**
- Create: `Tests/KurrentCoreTests/GRPCClientLifecycleCharacterizationTests.swift`

**Interfaces:**
- Consumes: `GRPCCore.GRPCClient`、`GRPCNIOTransportHTTP2Posix.HTTP2ClientTransport.Posix`
- Produces: 無生產程式碼。產出「行為事實」寫入本計畫 Task 1 結尾的結論欄

- [ ] **Step 1: 建立特性化測試檔**

```swift
//
//  GRPCClientLifecycleCharacterizationTests.swift
//  swift-kurrentdb
//
//  釘住 grpc-swift 2 的連線生命週期行為。這些測試不驗證 KurrentDB 的邏輯,
//  而是記錄我們所依賴的第三方行為 — 若上游改變,這些測試會先失敗。
//

import Testing
import GRPCCore
import GRPCNIOTransportHTTP2Posix
@testable import KurrentDB

@Suite("GRPCClient 連線生命週期特性", .serialized, .timeLimit(.minutes(1)))
struct GRPCClientLifecycleCharacterizationTests {

    /// 指向一個必定無法連線的位址(TEST-NET-1,RFC 5737 保留,不可路由)。
    /// 沿用 repo 既有的 `Endpoint.target` 與 `.http2NIOPosix`,與
    /// `GRPCClient+Additions.swift:17-20` 的建構方式一致。
    private func unreachableTransport() throws -> HTTP2ClientTransport.Posix {
        let endpoint = Endpoint(host: "192.0.2.1", port: 2113)
        return try .http2NIOPosix(
            target: endpoint.target,
            transportSecurity: .plaintext
        )
    }

    @Test("runConnections() 對無法連線的目標會拋錯,而非無限等待")
    func runConnectionsThrowsOnUnreachable() async throws {
        let client = GRPCClient(transport: try unreachableTransport())
        await #expect(throws: (any Error).self) {
            try await client.runConnections()
        }
    }

    @Test("連線 Task 被取消後,client 進入 stopped 狀態")
    func cancellingConnectionTaskStopsClient() async throws {
        let client = GRPCClient(transport: try unreachableTransport())
        let task = Task { try await client.runConnections() }
        task.cancel()
        _ = try? await task.value
        // 再次 run 應拋錯:client 只能執行一次
        await #expect(throws: (any Error).self) {
            try await client.runConnections()
        }
    }
}
```

- [ ] **Step 2: 執行測試,記錄實際行為**

Run: `swift test --filter GRPCClientLifecycleCharacterizationTests -v --no-parallel --disable-xctest --enable-swift-testing`

預期:兩個測試皆 PASS。

**若 `runConnectionsThrowsOnUnreachable` 逾時而非拋錯** —— 這就直接證實了 hang 的機制,且證明「吞錯」並非唯一成因。此時在 Task 4 必須額外處理「連線永不建立也永不拋錯」的情形。

- [ ] **Step 3: 將結論寫入本檔**

在本 Task 末尾以實際觀察填寫:

```
結論(由執行者填寫,不得留空):
- runConnections() 對無法連線目標:  [拋錯 / 無限等待]
- 取消連線 Task 後 client 狀態:      [stopped / 其他]
- 對 Task 4 的影響:                  [僅需 cancel / 需額外處理永不拋錯情形]
```

- [ ] **Step 4: Commit**

```bash
git add Tests/KurrentCoreTests/GRPCClientLifecycleCharacterizationTests.swift
git commit -m "[TEST] Characterize grpc-swift client lifecycle behaviour

Pins down whether runConnections() fails fast on an unreachable target and
whether cancelling its task stops the client. The connection-lifecycle fix
depends on these behaviours; recording them here makes an upstream change
surface as a test failure rather than a silent regression."
```

---

## Task 2: Subscription — teardown 提前佈署並解除 self 強持有

**Files:**
- Create: `Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift`
- Modify: `Subscription.swift:69-114`

**Interfaces:**
- Consumes: `Subscription.init(writer:)`、`send(state:)`、`onFinish(perform:)`(皆 internal,測試以 `@testable` 取用)
- Produces: 行為契約 —— teardown action 在 `source` 終止時必定執行,且不論 `.events` 是否曾被存取

- [ ] **Step 1: 寫失敗測試(T2 / T3 / T5)**

```swift
//
//  SubscriptionLifecycleTests.swift
//  swift-kurrentdb
//

import Testing
import Synchronization
@testable import KurrentDB

@Suite("Subscription 生命週期契約", .serialized, .timeLimit(.minutes(1)))
struct SubscriptionLifecycleTests {

    typealias Sub = PersistentSubscriptions.Subscription<PersistentSubscription.EventResult>

    /// 建立一個 subscription 並記錄 teardown 是否被呼叫。
    private func makeSubscription() -> (sub: Sub, tornDown: Mutex<Int>) {
        let writer = Sub.Writer()
        let sub = Sub(writer: writer)
        let counter = Mutex<Int>(0)
        sub.onFinish { _ in counter.withLock { $0 += 1 } }
        return (sub, counter)
    }

    @Test("T3:RPC 拋錯時 events 拋出且 teardown 執行")
    func rpcErrorTerminatesAndTearsDown() async throws {
        let (sub, tornDown) = makeSubscription()
        // 先同步驅動失敗,再 await —— 不使用任何計時
        sub.send(state: .finish(throwing: KurrentError.connectionClosed))

        await #expect(throws: (any Error).self) {
            for try await _ in sub.events { }
        }
        #expect(tornDown.withLock { $0 } == 1)
    }

    @Test("T2:迭代後跳出迴圈會觸發 teardown")
    func breakingOutTearsDown() async throws {
        let (sub, tornDown) = makeSubscription()
        sub.send(state: .finish())   // 正常結束

        for try await _ in sub.events { break }
        #expect(tornDown.withLock { $0 } == 1)
    }

    @Test("T5:teardown 重複觸發只執行一次")
    func teardownIsIdempotent() async throws {
        let (sub, tornDown) = makeSubscription()
        sub.send(state: .finish())
        for try await _ in sub.events { }
        sub.send(state: .finish())   // 再次終止

        #expect(tornDown.withLock { $0 } == 1)
    }
}
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `swift test --filter SubscriptionLifecycleTests -v --no-parallel --disable-xctest --enable-swift-testing`

預期:T2 / T3 應 PASS(現行程式碼在 `.events` 被存取時 teardown 是通的);T5 亦應 PASS(`callFinishActionOnce` 已冪等)。

**這是刻意的**:此步驟建立回歸基線,證明現行行為在「有存取 `.events`」時正確。Task 3 才會加入現行程式碼**做不到**的 T1。若此處有任何測試失敗,表示現況比 spec 描述更糟,須先回報再繼續。

- [ ] **Step 3: 將 teardown 佈署移入 init,並解除 bridge Task 的 self 強持有**

修改 `Subscription.swift`。將 `init` 改為(原 110-114 行):

```swift
        init(writer: Writer) {
            self.writer = writer
            self.tracker = SubscriptionTracker()
            self.source = AsyncThrowingStream<EventResult, Error>.makeStream()

            // teardown 必須從 handle 存在的那一刻起就可達,而非等到第一次存取
            // `.events`。對照 Streams.Subscribe.send 的作法。
            let writer = self.writer
            let tracker = self.tracker
            source.continuation.onTermination = { termination in
                writer.stop()
                tracker.callFinishActionOnce(termination: termination)
            }
        }
```

將 `events` 內的 bridge Task 改為明確 capture list(原 77 行起),並移除已移入 `init` 的職責(原 98-103 行):

```swift
                let source = self.source
                let tracker = self.tracker
                let task = Task { [source, tracker] in
                    do {
                        for try await eventResult in source.stream {
                            let yieldResult = continuation.yield(eventResult)
                            if let revision = eventResult.revision {
                                tracker.update(revision: revision)
                            }
                            if let position = eventResult.position {
                                tracker.update(position: position)
                            }
                            if case .terminated = yieldResult {
                                continuation.finish()
                                return
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }

                continuation.onTermination = { [source] _ in
                    // 串接到 init 佈署的 handler,由其執行 writer.stop 與 finish action
                    source.continuation.finish()
                    task.cancel()
                }
```

- [ ] **Step 4: 執行測試確認仍通過**

Run: `swift test --filter SubscriptionLifecycleTests -v --no-parallel --disable-xctest --enable-swift-testing`

預期:T2 / T3 / T5 全數 PASS。

Run: `swift build --build-tests`
預期:`Build complete!`,零 error。

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.Subscription.swift \
        Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift
git commit -m "[FIX] Arm persistent subscription teardown at init

Teardown was reachable only through the lazily-created \`events\` stream, so a
subscription whose events were never consumed could never close its RPC. Move
the termination handler to init and give the bridge task an explicit capture
list so it no longer strongly retains the subscription."
```

---

## Task 3: Subscription — 補上 deinit 兜底

**Files:**
- Modify: `Subscription.swift`(於 `init` 之後新增 `deinit`)
- Modify: `Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift`(新增 T1)

**Interfaces:**
- Consumes: Task 2 佈署於 `init` 的 `source.continuation.onTermination`
- Produces: 「handle 被丟棄即關閉連線」的行為,履行 `Subscription.swift:21-24` 的文件承諾

- [ ] **Step 1: 寫失敗測試(T1)**

加入 `SubscriptionLifecycleTests`:

```swift
    @Test("T1:從未存取 events 就丟棄,仍會觸發 teardown")
    func droppingWithoutIteratingTearsDown() async throws {
        // 等待實際的 teardown 訊號,而非猜測排程時機。
        // `deinit` 因 ARC 在 closure 結束時確定性觸發,但它驅動 `onTermination`
        // 的時機是 AsyncStream 的實作細節 —— 故等待訊號而非 Task.yield()。
        //
        // 若 teardown 從未發生,測試會停在此處,由 suite 的 `.timeLimit` 攔截。
        // 這正是設計意圖:斷言本身不含任何時間值,時間界限只存在於維運層。
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let writer = Sub.Writer()
            let sub = Sub(writer: writer)
            sub.onFinish { _ in continuation.resume() }
            // 刻意不存取 sub.events;離開此 closure 後 sub 立即被釋放。
            // 沒有 bridge task 持有它,故釋放是確定的。
        }
        // 能執行到此行,即代表 teardown 確實被觸發 —— 這就是斷言。
    }
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `swift test --filter "SubscriptionLifecycleTests/droppingWithoutIteratingTearsDown" -v --no-parallel --disable-xctest --enable-swift-testing`

預期:FAIL —— 測試會**停住直到 suite 的 1 分鐘上限**,因為現行程式碼無 `deinit`,handle 被丟棄時 `source` 從不終止,訊號永不到來。

**這個「以逾時呈現的失敗」就是本測試的紅燈**,並非測試寫壞。Task 3 Step 3 加入 `deinit` 後,它應在毫秒內通過。

- [ ] **Step 3: 新增 deinit**

於 `Subscription.swift` 的 `init` 之後加入:

```swift
        deinit {
            // 丟棄 handle 而從未迭代 `events` 時,仍須關閉底層 RPC。
            // 這履行本型別文件註解對「離開 scope 自動關閉」的承諾。
            // 觸發 init 佈署的 onTermination,其中 callFinishActionOnce 具冪等性。
            source.continuation.finish()
        }
```

- [ ] **Step 4: 執行測試確認通過**

Run: `swift test --filter SubscriptionLifecycleTests -v --no-parallel --disable-xctest --enable-swift-testing`

預期:T1–T3、T5 全數 PASS。

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/PersistentSubscriptions/PersistentSubscriptions.Subscription.swift \
        Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift
git commit -m "[FIX] Close persistent subscription RPC when the handle is dropped

The type's documentation states that letting a subscription go out of scope
stops the gRPC stream, but no deinit existed. Add one that finishes the source
continuation, which cascades into the teardown handler installed at init."
```

---

## Task 4: StreamStream — 連線 Task 的擁有權與取消

**前置**:必須先完成 Task 1 並填妥其結論欄。本 Task 的實作取決於該結論。

**Files:**
- Modify: `StreamStream.swift:28-45`

**Interfaces:**
- Consumes: `GRPCClient.runConnections()`、`beginGracefulShutdown()`
- Produces: 連線 Task 有明確擁有者,teardown 時被取消,不再無主殘留

**範圍已於 2026-07-20 縮減**:Task 1 證明取消 `runConnections()` 不產生任何錯誤,故本 Task **不**宣稱修復 hang,僅修復連線洩漏。hang 另案(spec §10)。

- [ ] **Step 1: 修改 perform,持有並取消連線 Task**

將 `StreamStream.swift:28-45` 改為:

> **2026-07-20 更新**:main 已併入 per-call-credentials,`perform` 現在多了
> `credentials: Authentication? = nil` 參數,且 metadata 改用
> `Metadata(from:overriding:)`。以下程式碼已對齊新簽名 —— 請勿改動這兩處。

```swift
        let client = try GRPCClient<HTTP2ClientTransport.Posix>(from: node)
        let connectionTask = Task {
            logger.debug("[\(Self.name)] Opening connection...")
            try await client.runConnections()
        }

        return try await withRethrowingError(usage: "\(Self.self).\(#function)") {
            let metadata = Metadata(from: node.settings, overriding: credentials)
            return try await send(connection: client, metadata: metadata, callOptions: callOptions) { error in
                if let error {
                    logger.error("The error is thrown in the response of StreamStream: \(error)")
                }

                logger.debug("[\(Self.name)] Closing connection...")
                // graceful shutdown 會等待進行中的 RPC 完成 —— 對長生命週期訂閱而言
                // 那可能永遠不會發生。依 GRPCClient.runConnections() 的文件,
                // 取消執行該方法的 Task 是中止所有工作的正規手段。
                client.beginGracefulShutdown()
                connectionTask.cancel()
            }
        }
```

- [ ] **Step 2: 建置並執行既有測試,確認無回歸**

Run: `swift build --build-tests`
預期:`Build complete!`,零 error。

Run: `swift test --filter SubscriptionLifecycleTests -v --no-parallel --disable-xctest --enable-swift-testing`
預期:T1–T3、T5 全數 PASS。

- [ ] **Step 3: 對真實伺服器執行完整訂閱測試**

需先啟動本機 KurrentDB(見 CLAUDE.md)。

Run: `swift test --filter PersistentSubscriptions -v --no-parallel --disable-xctest --enable-swift-testing`
預期:全數 PASS,且無 job 逾時。

- [ ] **Step 4: Commit**

```bash
git add Sources/KurrentDB/Core/Additions/Usecase/StreamStream.swift
git commit -m "[FIX] Own the gRPC connection task in StreamStream.perform

The task running runConnections() was unowned and its error discarded, so a
dead connection was never observed. Hold the task and cancel it on teardown —
graceful shutdown alone waits for in-flight RPCs, which for a long-lived
subscription may never complete."
```

---

## Task 5: 錯誤語意 — 連線死亡回報為 subscriptionDropped

**前置**:Task 1 結論須顯示連線失敗確實可被觀察。

**Files:**
- Modify: `Read.swift:85-87`、`AllStream.Read.swift`(對應位置)
- Modify: `Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift`(新增 T4)

**Interfaces:**
- Consumes: `KurrentError.subscriptionDropped(reason:lastRevision:lastPosition:)`(`KurrentError.swift:60`,現有但從未被拋出)、`Subscription.lastRevision` / `lastPosition`
- Produces: 連線失敗時 `.events` 拋出 `.subscriptionDropped`,攜帶續傳所需位置

- [ ] **Step 1: 寫失敗測試(T4)**

加入 `SubscriptionLifecycleTests`:

```swift
    @Test("T4:連線失敗回報為 subscriptionDropped 並攜帶續傳位置")
    func connectionFailureReportsDropped() async throws {
        let (sub, _) = makeSubscription()
        // 先收到一筆事件以建立 lastRevision,再同步驅動連線失敗
        sub.send(state: .finish(throwing: KurrentError.grpcConnectionError(
            cause: RPCError(code: .unavailable, message: "connection lost")
        )))

        var caught: KurrentError?
        do {
            for try await _ in sub.events { }
        } catch let error as KurrentError {
            caught = error
        }

        guard case .subscriptionDropped = caught else {
            Issue.record("預期 .subscriptionDropped,實得 \(String(describing: caught))")
            return
        }
    }
```

- [ ] **Step 2: 執行測試確認失敗**

Run: `swift test --filter "SubscriptionLifecycleTests/connectionFailureReportsDropped" -v --no-parallel --disable-xctest --enable-swift-testing`

預期:FAIL —— 實得 `.grpcConnectionError`,因為目前錯誤原封不動往上拋。

- [ ] **Step 3: 於 Read usecase 的 catch 轉換錯誤**

將 `Read.swift:85-87` 改為:

```swift
                } catch {
                    let kurrentError = error as? KurrentError
                    if kurrentError?.isNodeFailure == true {
                        // 連線層級失敗 —— 回報為訂閱中斷,並附上續傳所需位置
                        subscription.send(state: .finish(throwing: KurrentError.subscriptionDropped(
                            reason: "\(error)",
                            lastRevision: subscription.lastRevision,
                            lastPosition: subscription.lastPosition
                        )))
                    } else {
                        subscription.send(state: .finish(throwing: error))
                    }
                }
```

於 `AllStream.Read.swift` 的對應 `catch` 區塊套用相同修改。

- [ ] **Step 4: 執行測試確認通過**

Run: `swift test --filter SubscriptionLifecycleTests -v --no-parallel --disable-xctest --enable-swift-testing`
預期:T1–T5 全數 PASS。

Run: `swift build --build-tests`
預期:`Build complete!`

- [ ] **Step 5: Commit**

```bash
git add Sources/KurrentDB/PersistentSubscriptions/Usecase/ \
        Tests/PersistentSubscriptionsTests/SubscriptionLifecycleTests.swift
git commit -m "[FIX] Report connection-level subscription failures as subscriptionDropped

KurrentError.subscriptionDropped carries lastRevision and lastPosition for
resuming after a drop, but was declared and never thrown. Map node-level
failures onto it so callers get the position they need to resume."
```

---

## Task 6: CI 護欄

**Files:**
- Modify: `.github/workflows/swift-build-testing.yml`

**Interfaces:**
- Consumes: 無
- Produces: 失敗時保留所有 matrix cell 的結果;單一 job 不再無限佔用

- [ ] **Step 1: 加入 fail-fast: false 與 job timeout**

於 `build` job 的 `strategy` 下(`matrix:` 之前)加入一行:

```yaml
    strategy:
      fail-fast: false
      matrix:
```

於 `runs-on: ${{ matrix.os }}` 之後加入:

```yaml
    runs-on: ${{ matrix.os }}
    timeout-minutes: 30
```

對 `build-linux-distros` job 施以相同處理:`strategy` 下加 `fail-fast: false`,`runs-on: ubuntu-latest` 後加 `timeout-minutes: 30`。

- [ ] **Step 2: 驗證 YAML 合法且設定生效**

Run:
```bash
ruby -ryaml -e '
d = YAML.load_file(".github/workflows/swift-build-testing.yml")
d["jobs"].each { |name, j|
  puts "#{name}: fail-fast=#{j.dig("strategy","fail-fast").inspect} timeout=#{j["timeout-minutes"].inspect}"
}'
```

預期輸出:
```
build: fail-fast=false timeout=30
build-linux-distros: fail-fast=false timeout=30
```

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/swift-build-testing.yml
git commit -m "[CI] Keep the matrix running when one cell fails

fail-fast defaulted to true, so a single flaky cell cancelled the other 15 and
destroyed the evidence needed to tell a one-cell problem from a systemic one.
Add an explicit job timeout so a hang fails in 30 minutes instead of idling."
```

---

## Task 7: 壓測驗證(非驗收門檻)

**Files:** 無(僅執行)

**Interfaces:**
- Consumes: Task 2–5 的成果
- Produces: 對修正有效性的信心證據

- [ ] **Step 1: 迴圈執行持久訂閱測試**

需先啟動本機 KurrentDB。

Run:
```bash
for i in $(seq 1 30); do
  echo "=== run $i ==="
  swift test --filter PersistentSubscriptionAdvancedTests \
    --no-parallel --disable-xctest --enable-swift-testing 2>&1 | tail -3
done
```

預期:30 次全數 PASS,無 hang、無 crash。

**注意**:此為機率性驗證,**通過不代表證明無缺陷**,失敗才有決定性。依 spec §5.3,此步驟不作為驗收門檻。

- [ ] **Step 2: 記錄結果**

將 30 次執行的結果(通過次數 / 任何異常)回報,不需 commit。

---

## Self-Review

**1. Spec coverage**

| Spec 章節 | 對應 Task |
|---|---|
| §3 改動 1(連線擁有權) | Task 4 |
| §3 改動 2(init 佈署 teardown) | Task 2 |
| §3 改動 3(capture list) | Task 2 |
| §3 改動 4(deinit) | Task 3 |
| §4 錯誤語意 | Task 5 |
| §5.2 契約測試 T1–T5 | Task 2(T2/T3/T5)、Task 3(T1)、Task 5(T4) |
| §5.3 壓測 | Task 7 |
| §6 CI 護欄 | Task 6 |
| §9 證據強度(hang 機制未驗證) | Task 1 |

無未涵蓋項目。

**2. Placeholder scan**:Task 1 Step 3 的「結論」欄是**執行者必須填寫的實際觀察**,非計畫佔位符 —— 該值無法在執行前得知,且已明確標註「不得留空」。其餘各步驟皆含完整程式碼與確切指令。

**3. Type consistency**

- `Sub` typealias 於 Task 2 定義,Task 3、5 沿用
- `makeSubscription()` 於 Task 2 定義,回傳 `(sub: Sub, tornDown: Mutex<Int>)`;Task 5 以 `let (sub, _)` 取用,一致
- `send(state:)` 的 case:`.finish()` / `.finish(throwing:)`,與 `Subscription.swift:125-127` 一致
- `callFinishActionOnce(termination:)` 參數標籤與 `Subscription.swift:274` 一致
- `subscriptionDropped(reason:lastRevision:lastPosition:)` 參數與 `KurrentError.swift:60` 一致

**4. 已知風險**

Task 5 的測試 T4 依賴「`isNodeFailure` 為 true 的錯誤會走轉換分支」。`grpcConnectionError` 確實在 `isNodeFailure` 的清單內(`KurrentError.swift:131`)。若 Task 1 結論顯示連線失敗以其他錯誤型別呈現,Task 5 Step 3 的判斷條件須據實調整,並於該 Task 回報。
