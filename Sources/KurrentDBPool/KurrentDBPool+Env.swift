import Foundation
import KurrentDB

extension KurrentDBPool {
    /// `KURRENTDB_POOL_URLS` is a JSON array of strings rather than a custom-separated list.
    /// Each member is a full connection string, so a separator of our own (`,` and `;` were both
    /// tried) would need its own escaping scheme. JSON string escaping carries any connection
    /// string unchanged, so no separator or escaping scheme of our own is needed. The connection
    /// strings themselves must follow RFC 3986 (see `ClientSettings.parse(connectionString:policy:)`).
    ///
    /// Example:
    /// ```
    /// KURRENTDB_POOL_URLS=["esdb://admin:changeit@host1:2113?tls=false","esdb://admin:changeit@host2:2113?tls=false"]
    /// ```
    ///
    /// Errors only report which item (by index) is malformed; they never echo the raw string or
    /// the underlying parser error. A connection string may carry credentials (for example
    /// `esdb://admin:changeit@...`), and printing it in a fatalError would put the password in
    /// terminal and CI crash logs.
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
