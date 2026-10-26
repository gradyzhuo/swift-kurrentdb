import Foundation

/// Resource usage of the current process, from `getrusage(RUSAGE_SELF)`.
public enum ProcessUsage {
    /// CPU seconds (user, system) since process start and peak resident set size in bytes.
    /// `ru_maxrss` is bytes on macOS and KiB on Linux; the result is always bytes.
    public static func current() -> (user: Double, system: Double, maxRss: UInt64) {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        let raw = UInt64(max(usage.ru_maxrss, 0))
        #if os(Linux)
        let rss = raw * 1024
        #else
        let rss = raw
        #endif
        return (seconds(usage.ru_utime), seconds(usage.ru_stime), rss)
    }
}
