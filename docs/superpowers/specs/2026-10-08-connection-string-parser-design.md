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
