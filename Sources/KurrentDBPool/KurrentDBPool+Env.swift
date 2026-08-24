import Foundation
import KurrentDB

extension KurrentDBPool {
    /// 用 `;` 分隔每個 pool 成員,而不是 `,`——`ClientSettings.parse(connectionString:)`
    /// 本身支援用 `,` 表示同一個連線字串裡的多個 seed host（例如
    /// `esdb://node1:2113,node2:2113?tls=false` 是一個 seeds cluster）,如果拿 `,`
    /// 當 pool 成員分隔符,會把這種合法字串切成兩段互相看不懂的殘缺片段。
    ///
    /// 錯誤訊息只回報第幾個項目格式不合法,不回顯原始字串或底層 parser 的錯誤——
    /// 連線字串可能帶帳號密碼（例如 esdb://admin:changeit@...）,原樣印進
    /// fatalError 會讓密碼直接進到終端機／CI crash log。
    package static func settingsFromEnv(key: String = "KURRENTDB_POOL_URLS") -> [ClientSettings] {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return [] }
        return raw.split(separator: ";").enumerated().map { index, part in
            let trimmed = String(part).trimmingCharacters(in: .whitespaces)
            do {
                return try ClientSettings.parse(connectionString: trimmed)
            } catch {
                fatalError("\(key) 的第 \(index + 1) 個項目格式不合法")
            }
        }
    }
}
