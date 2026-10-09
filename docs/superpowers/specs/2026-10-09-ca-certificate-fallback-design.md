# 指定的 CA 讀不到時的處理 — 設計

日期：2026-10-09
處理：安全盤點 S06（指定 CA 無法讀取時悄悄改用系統信任庫）

## 1. 問題

指定 CA 有三個入口，最後都會呼叫 `ClientSettings.parseCertificate(path:)`：

| 入口 | 位置 |
|---|---|
| builder `.certificate(path:)` | `ClientSettings.swift`（約 441 行） |
| 連線字串 `tlsCaFile=` | `parse(connectionString:policy:)` |
| `fromEnv(key:)` | 透過 `parse` |

檔案不存在或內容為空時，`parseCertificate` 只記一行 warning 就回傳 `nil`。呼叫端於是不加入任何憑證，`certificates` 變成空的，`trustRoots` 就自動退回 `.systemDefault`。

結果：原本只打算信任自己私有 CA 的部署，在使用者完全不知情的情況下，改成接受整個系統信任庫。系統 CA 和 hostname 驗證都還在，所以這不是「關閉驗證」；但信任範圍被放大了。攻擊者只要拿到一張對該 hostname 有效、由任何公開 CA 簽發的憑證就能通過驗證。最常見的觸發原因是設定錯誤，例如 secret 掛載路徑寫錯。

## 2. 決定（owner，2026-10-09）

- 預設行為一律是**報錯**。
- 連線字串與環境變數（`fromEnv`）：`tlsCaFile` 讀不到就報錯，**不提供任何放寬選項**。
- 只有 builder 可以明確選擇「讀不到時改用系統信任庫」。
- 既有的 `certificate(path:)`：不改成 `throws`（避免破壞原始碼相容性）。讀不到時記住這件事，到 client 建立連線時報錯；同時把它標成 deprecated，指向新 API。

## 3. 公開 API

```swift
/// What a builder does when the CA file it was given cannot be read.
public enum CertificateFallback: Sendable, Equatable {
    /// No fallback: throw `KurrentError.initializationError`. The default everywhere.
    case none
    /// Leave the configured CA out and trust the system's root certificates instead.
    case systemTrustRoots
}

extension ClientSettings {
    /// Adds a CA certificate from a file. Throws when the file cannot be read, unless
    /// `fallback` is `.systemTrustRoots`.
    public func certificate(path: String, fallback: CertificateFallback) throws(KurrentError) -> Self

    @available(*, deprecated, message: "Use certificate(path:fallback:), which reports an unreadable file instead of widening trust.")
    public func certificate(path: String) -> Self   // 行為改變見 §4.3
}
```

- `fallback` **沒有預設值**。理由和 PR #160 一樣：有預設值的話，`certificate(path:)` 這個呼叫會同時符合兩個 overload，造成歧義；而且「放寬信任」必須明確寫出來。
- 命名參考 `JSONDecoder.dateDecodingStrategy` 這類「策略名詞」的慣例：`fallback:` 一個字，表達讀不到時改用什麼。`.none` 和 `Optional.none` 同名，但參數型別不是 Optional，所以沒有歧義。
- 用 enum 而不是 struct：這是兩個互斥行為的開關，不是會沿著獨立維度擴充的設定；使用者端也沒有理由對它做 `switch`。
- 「讀不到」的定義：檔案不存在、沒有讀取權限、或內容是空的。檔案讀得到但 PEM/DER 格式錯誤的情況，維持現有行為：在建立 TLS 時由 NIO 報錯。

## 4. 行為

### 4.1 連線字串 / `fromEnv`

`tlsCaFile` 讀不到時，`parse` 丟出 `KurrentError.internalParsingError(reason: "Parameter 'tlsCaFile' names a CA file that cannot be read.")`。

錯誤訊息**不包含路徑**，延續 PR #160 的規則：錯誤訊息只寫參數名稱，不寫值。路徑本身不是密碼，但規則不開例外，使用者自己知道設定的是哪個路徑。

### 4.2 `certificate(path:fallback:)`

- `.none`：讀不到就丟 `KurrentError.initializationError(reason:)`，reason 為 "The CA certificate file passed to certificate(path:fallback:) cannot be read."（不含路徑）。
- `.systemTrustRoots`：讀不到時回傳原本的 settings，不加入任何憑證，並記一行 `warning` log，例如 "configured CA certificate file is unreadable; using the system trust roots as requested"（不含路徑）。如果其他地方也沒有設定憑證，`trustRoots` 就是 `.systemDefault`。
- 讀得到：跟現在一樣，加入 `.file(path:format:)`。

### 4.3 舊的 `certificate(path:)`（deprecated）

讀不到時，不再靜默放寬信任：
- 在 settings 裡記錄「有一個指定的 CA 讀不到」，用 `package` 層級的屬性存，不公開。
- client 第一次建立連線時（`ConnectionProvider.makeClient`，包含 gossip discovery 走的那條路徑），丟 `KurrentError.initializationError(reason: "A CA certificate file passed to certificate(path:) cannot be read; refusing to fall back to the system trust roots.")`。
- `initializationError` 不屬於 node failure，所以不會被 `withRetry` 重試。
- 記錄了這個狀態時，`trustRoots` 也不能回傳 `.systemDefault`。即使某條路徑繞過了 `makeClient`，也不會因此放寬信任。

### 4.4 不變的部分

- `parseCertificate(path:)` 是 public API，回傳 `TLSConfig.CertificateSource?`，行為維持不變（第三方可能有用到）。內部改用一個會 throw 的 package helper。
- `certificate(source:)`、`certificates` 屬性、`crtInBundle`：不變。

## 5. 文件與 release note

- README 和 Getting started 裡的 `.certificate(path: "/path/to/ca.crt")` 範例，改成 `try .certificate(path: "/path/to/ca.crt", fallback: .none)`。Getting started 的 builder 表格加上新方法，並說明 `fallback: .systemTrustRoots` 什麼情況下適用（例如同一份設定在某些環境沒有掛載 CA，而且確實想用系統 CA）。
- 參數表的 `tlsCaFile` 一列補一句「讀不到時 `parse` 會報錯」。
- Release note：
  - 「`tlsCaFile` 或 `certificate(path:)` 指定的 CA 讀不到時，不再改用系統信任庫：`parse`/`fromEnv` 直接報錯，`certificate(path:)`（已 deprecated）會在建立連線時報錯。」
  - 「新增 `certificate(path:fallback:)`（`CertificateFallback.none` / `.systemTrustRoots`）。」

## 6. 測試

- `parse`：`tlsCaFile` 指向不存在的檔案、空檔案、沒有讀取權限的檔案時都報錯，而且 reason 不含路徑；指向可讀的 PEM 時，`trustRoots` 是 `.certificates`。
- `certificate(path:fallback: .none)`：讀不到時報錯，reason 不含路徑。
- `certificate(path:fallback: .systemTrustRoots)`：讀不到時 `certificates` 不變；如果原本是空的，`trustRoots` 為 `.systemDefault`。
- deprecated 的 `certificate(path:)`：讀不到時，對 `ConnectionProvider.acquire(_:)` 的呼叫丟 `initializationError`（離線測試，不需要 server），而且 `trustRoots` 不是 `.systemDefault`；讀得到時行為與現在相同。
- 既有 live 測試使用 `certificate(source: .crtInBundle(...))`，不受影響。
- 文件裡的 snippet 必須能編譯（`scripts/check-doc-snippets.sh`），而且不能再用 deprecated 的 API。

## 7. 不在範圍內

- 檔案讀得到但格式錯誤的處理（維持由 NIO 報錯）。
- `tlsVerifyCert(false)` 的範例（盤點的附註）、gossip endpoint 的信任邊界。
- 2.x → 3.0 是否移除 `certificate(path:)`：之後交給 migration guide 決定。
