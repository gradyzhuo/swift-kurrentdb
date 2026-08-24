import Foundation
import KurrentDB

extension KurrentDBPool {
    package static func settingsFromEnv(key: String = "KURRENTDB_POOL_URLS") -> [ClientSettings] {
        guard let raw = ProcessInfo.processInfo.environment[key] else { return [] }
        return raw.split(separator: ",").map { part in
            do {
                return try ClientSettings.parse(connectionString: String(part))
            } catch {
                fatalError("KURRENTDB_POOL_URLS 有不合法的連線字串: \(part), error: \(error)")
            }
        }
    }
}
