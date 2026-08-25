import Foundation
import KurrentDB

extension KurrentDBPool {
    /// `KURRENTDB_POOL_URLS` 是一個 JSON 字串陣列,而不是自己發明的分隔符——
    /// 之前先後試過 `,` 跟 `;` 當 pool 成員分隔符,兩個都撞到同一類問題：
    /// `ClientSettings.parse(connectionString:)` 底層的帳密解析器只排除
    /// `:`／`@` 兩個字元,意味著密碼理論上可以包含任何其他字元，包括我們
    /// 挑來當分隔符的那個。只要密碼裡剛好出現同一個字元（例如
    /// `esdb://admin:pa;ss@host:2113`），自製分隔符就會把合法字串切成兩段
    /// 殘缺、彼此都解析不出來的片段。JSON 陣列用標準的字串跳脫規則
    /// （`\"`、`\\` 等）處理任何字元，不會有這個問題——這是唯一不需要自己
    /// 發明一套跳脫規則就能正確處理任意內容的做法。
    ///
    /// 範例：
    /// ```
    /// KURRENTDB_POOL_URLS=["esdb://admin:changeit@host1:2113?tls=false","esdb://admin:changeit@host2:2113?tls=false"]
    /// ```
    ///
    /// 錯誤訊息只回報第幾個項目格式不合法,不回顯原始字串或底層 parser 的錯誤——
    /// 連線字串可能帶帳號密碼（例如 esdb://admin:changeit@...）,原樣印進
    /// fatalError 會讓密碼直接進到終端機／CI crash log。
    package static func settingsFromEnv(key: String = "KURRENTDB_POOL_URLS") -> [ClientSettings] {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return [] }
        guard let data = raw.data(using: .utf8),
              let urls = try? JSONDecoder().decode([String].self, from: data)
        else {
            fatalError("\(key) 必須是一個 JSON 字串陣列,例如 [\"esdb://host1:2113\",\"esdb://host2:2113\"]")
        }
        return urls.enumerated().map { index, url in
            do {
                return try ClientSettings.parse(connectionString: url)
            } catch {
                fatalError("\(key) 的第 \(index + 1) 個項目格式不合法")
            }
        }
    }
}
