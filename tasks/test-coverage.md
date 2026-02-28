# Test Coverage Audit

> Generated: 2026-02-28 (updated)

## Summary

| Suite | Files | Active @Test | Commented Out |
|-------|-------|-------------|---------------|
| StreamsTests | 4 | 35 | 0 |
| ProjectionsTests | 2 | 16 | 0 |
| PersistentSubscriptionsTests | 2 | 11 | 0 |
| UsersTests | 1 | 7 | 0 |
| MonitoringTests | 1 | 3 | 0 |
| GossipTests | 1 | 3 | 0 |
| OperationsTests | 1 | 6 | 0 |
| KurrentCoreTests | 6 | 67 | 0 |
| MockClientTests | 2 | 26 | 0 |
| **Total** | **20** | **174** | **0** |

---

## Existing Tests

### StreamsTests

| File | Test | Scenario |
|------|------|----------|
| StreamsTests.swift | Stream not found → throws error | 讀不存在的 stream → `resourceNotFound` |
| StreamsTests.swift | Append events → read back | append 2 events、讀回、驗證 revision |
| StreamsTests.swift | Append to multiple streams | 多 stream 同時 append（TaskGroup） |
| StreamsTests.swift | Set/Get stream metadata | cache control、maxAge、ACL roundtrip |
| StreamsTests.swift | Subscribe before append | 先訂閱再 append，驗證收到事件 |
| StreamsTests.swift | Subscribe to `$all` with position filter | 訂閱 `$all` + position `.end` + event type filter |
| StreamsTests.swift | Subscribe `$all` with event type prefix | prefix 過濾 |
| StreamsTests.swift | Subscribe `$all` exclude system events | `excludeSystemEvents()` 過濾 |
| StreamsTests.swift | Subscribe `$all` with stream name filter | stream name prefix 過濾 |
| StreamsTests.swift | Subscribe `$all` with unmatched filter | 不符合的 prefix → 收不到事件 |
| StreamsTests.swift | ACL encoding/decoding roundtrip | systemStreamAcl、userStreamAcl |
| StreamsTargetTests.swift | SpecifiedStream 建立（identifier / string / literal）| 型別與 encoding 驗證 |
| StreamsTargetTests.swift | AllStreams / MultiStreams static property | 型別安全 |
| StreamsTargetTests.swift | ProjectionStream by event type / stream prefix | `$et-`、`$ce-` 格式 |
| StreamsTargetTests.swift | String conforms to SpecifiedStreamTarget | 協議一致性 |
| StreamsTargetTests.swift | KurrentDBClient factory methods integration | 5 種 target 的 client 工廠方法 |
| StreamsTargetTests.swift | Empty name、special chars、versioned types | 邊界值 |
| AllStreamsTests.swift | Read `$all` 排除 system events | hasPrefix("$") 過濾 |
| AllStreamsTests.swift | Read `$all` from specific position with limit | 指定 commit/prepare position + maxCount |
| StreamsReadTests.swift | Forward read from start | 順序驗證 |
| StreamsReadTests.swift | Backward read from end | 反向順序 |
| StreamsReadTests.swift | Read with limit | maxCount 限制 |
| StreamsReadTests.swift | Read from specific revision | revision 定位 |
| StreamsReadTests.swift | Delete stream → `resourceNotFound` | 刪除後讀取報錯 |
| StreamsReadTests.swift | Tombstone → append blocked | tombstone 後無法 append |
| StreamsReadTests.swift | Stale revision → `wrongExpectedVersion` | `.at(99)` 但 stream 在 revision 0 |
| StreamsReadTests.swift | `.noStream` to existing stream → `wrongExpectedVersion` | stream 已存在，卻聲稱不應存在 |
| StreamsReadTests.swift | Concurrent appends at same revision — exactly one wins | 兩個 writer 搶 `.at(0)`，一成功一 conflict |

---

### ProjectionsTests

| File | Test | Scenario |
|------|------|----------|
| ProjectionsTests.swift | Create continuous projection | 建立並驗證 mode |
| ProjectionsTests.swift | Create one-time projection | 計數確認 |
| ProjectionsTests.swift | Disable projection → stopped | 狀態轉換 |
| ProjectionsTests.swift | Disable then enable → running | 雙向狀態 |
| ProjectionsTests.swift | Abort projection | abort → reset |
| ProjectionsTests.swift | Get status for system projection `$by_category` | 系統投影查詢 |
| ProjectionsTests.swift | Get projection state | CountResult 解碼 |
| ProjectionsTests.swift | Get projection result | Int 解碼 |
| ProjectionsTests.swift | List continuous projections | `.anyContinuous` 列表 |
| ProjectionsTests.swift | List transient projections | `.anyTransient` 列表 |
| ProjectionsTests.swift | Status string parsing | "Aborted/Stopped" 多狀態解析 |
| ProjectionsAdvancedTests.swift | Update projection query | disable 後更新 query |
| ProjectionsAdvancedTests.swift | Continuous list contains new projection | 建立後出現在列表 |
| ProjectionsAdvancedTests.swift | Deleted projection absent from list | 刪除後不出現 |
| ProjectionsAdvancedTests.swift | getProjectionDetail returns mode and name | 詳細資訊 |
| ProjectionsAdvancedTests.swift | Reset after abort → Stopped | 狀態機 |

---

### PersistentSubscriptionsTests

| File | Test | Scenario |
|------|------|----------|
| PresistentSubscriptionTests.swift | Create subscription for stream | 建立後列出確認 |
| PresistentSubscriptionTests.swift | Subscribe stream, append, ACK | 完整 happy path |
| PresistentSubscriptionTests.swift | Subscribe `$all`, append, ACK | `$all` 訂閱 |
| PersistentSubscriptionAdvancedTests.swift | NACK with park action | park 到 dead-letter queue，不拋錯 |
| PersistentSubscriptionAdvancedTests.swift | NACK with retry action | retry 後重新收到事件，deliveries == 2 |
| PersistentSubscriptionAdvancedTests.swift | getInfo returns correct group/source | groupName + eventSource 驗證 |
| PersistentSubscriptionAdvancedTests.swift | getInfo for `$all` subscription | eventSource == "$all" |
| PersistentSubscriptionAdvancedTests.swift | Update subscription settings | maxRetryCount = 5，getInfo 確認 |
| PersistentSubscriptionAdvancedTests.swift | List subscriptions for a stream | filterStream → 含 groupName |
| PersistentSubscriptionAdvancedTests.swift | Delete removes from list | delete 後 filterStream → 不含 groupName |
| PersistentSubscriptionAdvancedTests.swift | Replay parked messages | park → replayParked → 收到事件 → ACK |

---

### UsersTests

| Test | Scenario |
|------|----------|
| Create user → return details | 建立並驗證 name、fullName、groups、disabled |
| Create user with variadic groups | `.ops, .admins` |
| Get user details | 詳情 stream 迭代 |
| Disable then enable | 雙向 enable/disable |
| Update fullName | password 確認後更新 |
| Change password | origin 驗證後更換 |
| Reset password | 管理員重置（不需 origin）|

---

### MonitoringTests

| Test | Scenario |
|------|----------|
| Retrieve server statistics | `stats()` → non-empty dict |
| Stats with custom refresh interval | `refreshTimePeriodInMs: 5000` |
| Stats with metadata | `useMetadata: true` |

---

### GossipTests

| Test | Scenario |
|------|----------|
| Read cluster → member info | isAlive、httpEndPoint 驗證 |
| At least one node with known state | 8 種已知狀態之一 |
| Read cluster with custom timeout | `.seconds(10)` |

---

### OperationsTests

| Test | Scenario |
|------|----------|
| Start a scavenge returns non-empty scavengeId | `startScavenge(threadCount:startFromChunk:)` → `.started` or `.inProgress` |
| Start then stop a scavenge | `startScavenge` → `stopScavenge` → `.stopped` or `.inProgress` |
| Merge indexes completes without error | `mergeIndexes()` |
| Restart persistent subscriptions subsystem | `restartPersistentSubscriptions()` |
| Set node priority | `setNodePriority(priority: 0)` |
| Resign node | `resignNode()` — re-election on 3-node cluster |

---

### KurrentCoreTests

| File | Tests | Topics |
|------|-------|--------|
| ConnectionStringParserTests.swift | 3 | scheme、host、endpoint 解析 |
| EventDataTests.swift | 12 | UUID、type、payload、metadata、content-type |
| ProjectionStatusTests.swift | 15 | status 解析、複合狀態、roundtrip |
| StreamIdentifierTests.swift | 11 | name、encoding、category、equality、literal |
| StreamMetadataTests.swift | 18 | builder pattern、ACL、JSON roundtrip |
| SubscriptionFilterTests.swift | 14 | event type / stream name filter、window、builder |

---

### MockClientTests

26 個測試涵蓋：
- `KurrentDBClientProtocol` 符合性
- 所有 factory method 的呼叫記錄（streams、persistentSubscriptions、users、operations、monitoring）
- 5 個 domain service 整合情境（OrderEventService、SubscriptionManager、UserAdminService、ServerAdminService）

---

## Missing Tests

### 🟡 中優先 — 已有功能的邊界與錯誤路徑

| 缺少的測試 | 類別 | 說明 |
|-----------|------|------|
| Tombstone stream → read blocked | Streams | tombstone 後讀取應拋 `resourceDeleted`（目前只測了 append 被 block）|
| Create duplicate projection → error | Projections | 相同名稱第二次建立應拋 `resourceAlreadyExists` |
| Create transient projection lifecycle | Projections | transient 的完整 lifecycle（目前只有 one-time 和 continuous）|
| Create user duplicate login → error | Users | 建立同名使用者應拋 `resourceAlreadyExists` |
| Enable non-existent projection → error | Projections | 操作不存在的投影應拋 `resourceNotFound` |

---

### 🟢 低優先 — 覆蓋率增強

| 缺少的測試 | 類別 | 說明 |
|-----------|------|------|
| KurrentDB_V1 deprecated methods compile | KurrentDB_V1 | import KurrentDB_V1 後 deprecated 方法可用並有警告 |
| ClientSettings cluster modes | Core | `.seeds()`、`.dns()` ClusterMode builder 解析 |
| Stream subscription with `resolveLinkTos` | Streams | 連結事件解析 |
| Multi-consumer persistent subscription | PersistentSubscriptions | 同一 group 多個 consumer 競爭消費（competing consumer 核心概念）|
| Read `$all` with `resolveLinkTos` on projection stream | Streams | projection emit 的 link event 解析 |
| `readCluster` timeout actually triggers | Gossip | timeout 真的觸發的情境（目前只測回傳結果）|
