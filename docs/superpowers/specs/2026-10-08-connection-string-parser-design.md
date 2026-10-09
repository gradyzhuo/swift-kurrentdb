# 連線字串 parser 重寫 — 設計

日期：2026-10-08
處理：安全盤點 S01（authority 與 query 沒有隔離）、S03（throws API 會 trap）

## 1. 問題

`ClientSettings.parse(connectionString:)` 把**整串**輸入分別丟給四個 regex parser（scheme、endpoint、credentials、query），每個 parser 都在整串裡自己找規則，彼此不知道對方的邊界。在 main `8fbf5f4c` 實測：

| 輸入（密碼部分） | 現在的結果 |
|---|---|
| `admin:pa&tls=false&x=y@host` | 密碼原樣，但 `tls=false` 也生效 → 明文連線 |
| `admin:p@ss@host` | 程序 trap（signal 6） |
| `admin:p:ss@host` | 帳號變 `p`、密碼變 `ss` |
| `admin:p%26ss@host` | 密碼是字面 `p%26ss`，不解碼 → 認證失敗 |
| `admin:pa?tls=false@host` | 「沒有 host」錯誤 |
| `host:2113?connectionName=svc:a@b` | 憑空多出帳號 `2113?connectionName=svc`、密碼 `a` |
| `?tls=true&TLS=false` | 重複 key → `Dictionary(uniqueKeysWithValues:)` trap |
| `?keepAliveInterval=18446744073709551615&keepAliveTimeout=1` | `* 1000` 溢位 trap |

另外：不合法的值（`tls=abc`、`nodePreference=foo`、非數字）目前**靜默改用預設值**，打錯字的設定不會被發現。

結論：含 `@ : & ? %` 的密碼目前沒有任何寫法是正確的；有兩種輸入會讓程序崩潰。

## 2. 目標 / 非目標

目標
- 先依 RFC 3986 的結構切出 scheme / authority / query，各段只由各自的 parser 處理。
- userinfo 與 query 做 percent-decoding，讓任何密碼都有正確的寫法。
- 任何輸入都只會得到 `ClientSettings` 或 `KurrentError`，**絕不 trap**。
- 錯誤訊息只指出哪個欄位或哪個 key 有問題，不回顯輸入值（延續 S05）。

非目標（另開）
- 各參數的單位或預設值與其他官方 client 對齊。現有落差：文件寫 `gossipTimeout` 預設 3 秒，connection string 路徑實際給 5 秒；Python client 的 keepAlive 用毫秒，本 SDK 用秒。改單位是 breaking，不混在這裡。
- IPv6 字面位址（`[::1]:2113`）。現在不支援，這次也不加，但新結構不能讓之後加不進去。
- S06（CA 讀不到時退回系統信任庫）、`init(stringLiteral:)` 的 `fatalError` 行為。

## 3. 語法（本 SDK 接受的子集）

```
connection-string = scheme "://" [ userinfo "@" ] hosts [ "/" ] [ "?" query ]
scheme            = "esdb" | "kurrentdb" | "kurrent" | "kdb"   ; 可加 "+discover"，大小寫不敏感
userinfo          = username ":" password                        ; 兩者都要 percent-decode
hosts             = host [ ":" port ] *( "," host [ ":" port ] )
query             = param *( "&" param )
param             = key "=" value                               ; 兩者都要 percent-decode
```

切分規則依序執行，每一步只看上一步留下的片段：

1. **scheme**：找第一個 `://`，左邊是 scheme，必須是上面列的其中一種。
2. **authority**：`://` 之後，到第一個 `/`、`?` 或 `#` 為止（RFC 3986 §3.2）。
3. **userinfo**：authority 裡**最後一個** `@` 的左邊；沒有 `@` 就沒有 credentials。
   - 用「最後一個」`@`，是為了讓沒編碼的 `@` 密碼也照舊能用（`admin:p@ss@host` → 密碼 `p@ss`），避免現有寫法壞掉。
   - username 和 password 以**第一個** `:` 分開，所以 password 可以含 `:`。username 不能含 `:`，要用就寫 `%3A`。
   - 沒有 `:`、或 username 為空 → 錯誤。
4. **hosts**：`@` 右邊（沒有 `@` 就是整個 authority）以 `,` 分開。每段 `host[:port]`：host 不可為空；port 省略時是 2113，有寫就必須是 1–65535 的十進位數字。
   - host 只能含 ASCII 字母、數字、`-`、`_`、`.`，label 不可為空；如果每個 label 都是純數字，就必須是四段、每段 0–255 的 IPv4。這條沿用現有 `EndpointParser` 的行為（`192.168` 會被拒絕），既有測試有涵蓋。
5. **query**：第一個 `?` 之後，以 `&` 分開，空的片段（例如結尾多一個 `&`）忽略；每項以第一個 `=` 分成 key / value，所以 value 可以含 `=`；key 比較時不分大小寫。`+` 不會被當成空白（這是 form encoding 的規則，不是 RFC 3986），檔案路徑裡的 `+` 照原樣保留。
   - authority 後面只允許接一個 `/`，再接 `?query`；其他 path（例如 `/foo`）都是錯誤。
6. **fragment**（`#…`）：拒絕。KurrentDB 連線字串沒有 fragment 的用途；接受它反而會讓 `p#ss` 這種密碼被靜默截斷。

percent-decoding：`%XX`（十六進位）解碼成位元組，結果必須是合法的 UTF-8；格式錯誤（`%zz`、`%4`）或解出非 UTF-8 → 錯誤。

**哪些字元在密碼裡必須編碼**：`/ ? #`（會提早結束 authority），以及 `%` 本身。其他字元，包括 `@ : & = $ !`，都可以直接寫。文件會附一個 `addingPercentEncoding` 的範例。

## 4. 值的驗證

| 情況 | 處理 |
|---|---|
| 重複 key（不分大小寫） | 錯誤：`Duplicate connection string parameter 'tls'` |
| key 沒有 `=`、key 為空 | 錯誤 |
| `tls` / `tlsVerifyCert` 不是 `true` / `false`（不分大小寫） | 錯誤 |
| `nodePreference` 不在列舉內 | 錯誤 |
| 數值參數不是十進位整數、超出型別範圍、≤ 0（`defaultDeadline` 例外，見下） | 錯誤 |
| 時間類參數（`gossipTimeout`、`discoveryInterval`、`keepAlive*`、`defaultDeadline`）換算成奈秒後超過 `Int64` | 錯誤（用 `multipliedReportingOverflow` 檢查）。這樣下游轉成 NIO `TimeAmount` 或計算 deadline 時就不可能溢位 |
| `defaultDeadline` | 正整數；沿用 PR #156 的語意：不設 = 沒有 deadline |
| `userCertFile` 只給一個、或兩個都給但 `tls=false` | 錯誤（後者沿用現有行為） |
| 未知 key | 錯誤（§7 決定 1） |

錯誤一律是 `KurrentError.internalParsingError(reason:)`。不新增 enum case，因為對公開 enum 加 case 會讓使用者那邊窮舉的 `switch` 編譯失敗。reason 只寫參數名稱和期望的格式，**不放值**。

## 5. 結構

- 新增 `Core/ClientSettings/Parser/ConnectionString.swift`：`package struct ConnectionString`，負責第 3 節的切分與 decode，產出 `scheme`、`credentials: (username, password)?`、`hosts: [Endpoint]`、`parameters: [String: String]`（key 一律轉小寫）。純值型別，沒有 regex，也沒有 `class`。
- `ClientSettings.parse(connectionString:)` 只負責把 `ConnectionString` 映射成設定，以及第 4 節的值驗證。
- 刪除 `URLSchemeParser`、`EndpointParser`、`UserCredentialsParser`、`QueryItemParser`、`ConnctionStringParser` 這幾個 protocol 和 class。它們只被 `parse` 和 `ConnectionStringParserTests` 使用。`URLScheme` enum 保留。
- 公開 API 完全不變：`parse(connectionString:)`、`fromEnv`、`init(stringLiteral:)` 的簽章都一樣。

## 6. 測試

- 第 1 節表格的每一列都變成測試：要嘛解析出正確的值，要嘛丟 `KurrentError`。`p@ss` 這列要解析成功，而且密碼是 `p@ss`。
- percent-decoding：`p%26ss` → `p&ss`、`p%40ss` → `p@ss`、`%E5%AF%86` → `密`（之後 S07 會讓它在送出時失敗，但解析本身要正確）、`%zz` 和 `%4` → 錯誤。
- 結構：query 裡出現 `@` 不會變成 credentials；authority 不會吃到 query 的 `&`；`#` 被拒絕；多個 host 加上 `+discover`；預設 port。
- 第 4 節表格每一列都有對應的負向測試，並斷言錯誤訊息不含值。
- **不 trap 的保證**：用固定 seed 產生 10,000 個隨機字串（字母表含 `:@/?#&=%,` 等符號、數字和非 ASCII），對每個斷言 `parse` 只會回傳設定或丟 `KurrentError`。這是確定性的測試，不是 fuzz 服務。
- 現有 `ConnectionStringParserTests` 的 36 個案例，凡是合法輸入的全部保留並改呼叫 `parse`，確保現有寫法不會壞。

## 7. 決定（2026-10-08，已確認）

1. 未知的 query key → **錯誤**（選項 a）。
2. 密碼裡的字面 `%` → **照 RFC 3986 percent-decoding**；寫進 release note。

以下保留當時列出的選項與理由。

### 原始選項

1. **未知的 query key**：
   - (a) 錯誤（推薦）。打錯字的 `tlsVerifyCrt=false` 現在會被靜默忽略，使用者以為已經關掉驗證、其實沒有，反過來也一樣。拒絕最安全，代價是放了其他 client 專用參數的連線字串會被拒。
   - (b) 忽略並記 warning log，相容性最好，但打錯字還是不容易發現。
2. **密碼裡的字面 `%`**：percent-decoding 之後，原本寫成 `p%41ss` 的密碼會變成 `pAss`；如果 `%` 後面不是合法的兩位十六進位，會直接報錯。這是唯一一個**現在能用、改了之後行為會不一樣**的合法寫法。我認為該照 RFC 走，並寫進 release note。另一個選項是只在「整段都是合法 percent-encoding」時才解碼，但那會讓同一個字串的意思取決於內容，我不推薦。

## 8. Release note 草稿

- 連線字串的 userinfo 和 query 值現在會做 percent-decoding。密碼含 `/ ? # %` 時要先編碼（例如 `password.addingPercentEncoding(withAllowedCharacters: .urlPasswordAllowed)`）。
- 重複參數、格式錯誤的值、溢位，現在都會丟 `KurrentError`。以前分別是程序崩潰或靜默改用預設值。
- 未知的參數會被拒絕（`KurrentError.internalParsingError`，訊息裡列出參數名稱）。
- 只給 `userCertFile` 或只給 `userKeyFile` 現在會報錯；以前會靜默忽略，改用帳密認證。


## 9. 修訂（2026-10-09，final review 後，已確認）

最終 review 發現：寬鬆的寫法（authority 以**最後一個** `@` 切開、query 值什麼字元都收）會留下 S01 的殘留。例如 `esdb://admin:2113?tls=false&connectionName=x@db.example.com` 會被解析成 host `admin:2113`、沒有帳密、`tls=false`，不報錯、直接用明文連到錯的 host。owner 決定改成嚴格依 RFC 3986，並保留一個 policy 參數作為統一入口。

### 9.1 Policy 參數（依 Target pattern）

- 照 `StreamsTarget` 的寫法：`public protocol ConnectionStringPolicy: Sendable {}` 是**沒有任何 requirement 的 marker protocol**；`public struct RFC3986Policy: ConnectionStringPolicy`；`extension ConnectionStringPolicy where Self == RFC3986Policy { public static var rfc3986: RFC3986Policy }`。
- 入口是每個 policy 各自一個具體的 overload，不是對 protocol 泛型：`ClientSettings.parse(connectionString: String, policy: RFC3986Policy = .rfc3986)`、`ClientSettings.fromEnv(key: String = …, policy: RFC3986Policy = .rfc3986)`；`init(stringLiteral:)` 使用預設值。既有呼叫不需要改。
- 為什麼不做泛型、protocol 也沒有 requirement：package 外的型別雖然可以遵循這個 marker protocol，但不會有對應的 `parse` overload，所以沒有人能塞進一個放寬安全規則的 policy。要新增 policy，就是在 package 內新增一個 struct 和一個 overload。這也是 Target pattern 的作法：哪些操作可用，由 constrained extension 決定。
- 不提供不安全或寬鬆的 policy。需要任意字元密碼的使用者，可以 percent-encode，或改用 `ClientSettings.authenticated(.credentials(username:password:))`。

### 9.2 `.rfc3986` 的字元規則（取代 §3 第 3、5 點的寬鬆部分）

- 解析前先 trim 掉字串**頭尾**的空白和換行（`fromEnv` 讀到的 k8s secret 常帶結尾換行）；字串中間出現的空白一律報錯。
- authority 裡最多只能有**一個** `@`。userinfo 的原始位元組只接受 RFC 3986 userinfo 允許的字元：`A–Z a–z 0–9 - . _ ~`、`! $ & ' ( ) * + , ; =`、`:` 和 `%XX`。username 與 password 以第一個 `:` 分開，所以 password 可以含 `:`。
- query 的 key 和 value，原始位元組只接受 `A–Z a–z 0–9 - . _ ~`、`! $ ' ( ) * + , ;`、`:`、`/`、`?`、`%XX`；value 另外可以含 `=`。`&` 是分隔符號。**沒編碼的 `@` 刻意拒絕**（RFC 允許，但這正是上面攻擊需要的條件），要寫成 `%40`。
- 其他字元，包括空白、非 ASCII、控制字元、`"` `<` `>` `\` `^` `` ` `` `{` `|` `}`，只要沒編碼都會報錯。
- 錯誤訊息要給出修法。例如 query 裡有 `@` 時：說明要寫成 `%40`，並指出任意字元的密碼可以改用 `.authenticated(.credentials(...))`。

### 9.3 其他修正

- `defaultDeadline` 不能在 32 位元 `Int` 平台（watchOS arm64_32）trap：用 `Int(exactly:)` 轉換，失敗就報錯。
- 錯誤訊息裡回顯的 key 名稱：跳脫非可列印字元與非 ASCII 字元，並限制在 64 個字元以內。
- host 以 `[` 開頭時，錯誤訊息要明確說「不支援 IPv6 位址字面值」。
- host 最後一個字元是 `.` 時（FQDN，例如 `node.svc.cluster.local.`）照樣接受，舊 parser 也接受這種寫法。
- `ConnectionString.swift` 要明確 `import Foundation`。

### 9.4 對 §1 表格與既有測試的影響

- `admin:p@ss@host` → 報錯，要寫成 `p%40ss`。舊 parser 遇到它會 trap，所以不會讓原本能用的寫法壞掉。
- `host:2113?connectionName=svc:a@b` → 報錯。`ClientSettingsParsingTests.testAtSignInQueryParam`（`connectionname=user@domain`）改成斷言會報錯，另外新增 `user%40domain` 的成功案例。這是 owner 同意的相容性代價。

### 9.5 Release note 補充

- 連線字串依 RFC 3986 嚴格解析：帳號、密碼和參數值裡的 `@ / ? # %`、空白、非 ASCII 都必須 percent-encode。字串頭尾的空白和換行會被忽略。
- 新增 `policy:` 參數：`ConnectionStringPolicy` protocol 加上 `RFC3986Policy`，用 `.rfc3986` 傳入，也是預設值。
- 其他 client 才有的參數（例如 `throwOnAppendFailure`），以及 `keepAliveInterval=-1` 這種用 -1 停用的寫法，現在都會報錯。
- 只寫 `admin@host`（有 `@` 但沒有 `:`）現在會報錯；以前是靜默地不帶帳密連線。
