import Foundation

/// Resource usage of the current process: CPU from `getrusage(RUSAGE_SELF)`, peak RSS from `VmHWM` on Linux.
public enum ProcessUsage {
    /// CPU seconds (user, system) since process start and peak resident set size in bytes.
    ///
    /// On Linux `ru_maxrss` is not this process's peak: the kernel folds the pre-exec address space's high-water mark
    /// into it, so a driver spawned by the orchestrator reports at least the orchestrator's peak. `VmHWM` in
    /// /proc/self/status belongs to the address space created by exec, so it is used there. `ru_maxrss` (bytes on
    /// macOS) is the fallback.
    public static func current() -> (user: Double, system: Double, maxRss: UInt64) {
        var usage = rusage()
        #if os(Linux)
        getrusage(RUSAGE_SELF.rawValue, &usage)  // Glibc imports RUSAGE_SELF as an enum, getrusage takes Int32.
        #else
        getrusage(RUSAGE_SELF, &usage)
        #endif
        func seconds(_ t: timeval) -> Double { Double(t.tv_sec) + Double(t.tv_usec) / 1_000_000 }
        let raw = UInt64(max(usage.ru_maxrss, 0))
        #if os(Linux)
        let rss = peakResidentFromProcStatus() ?? raw * 1024
        #else
        let rss = raw
        #endif
        return (seconds(usage.ru_utime), seconds(usage.ru_stime), rss)
    }

    /// `VmHWM` of /proc/self/status in bytes, or nil when it cannot be read.
    static func peakResidentFromProcStatus() -> UInt64? {
        guard let status = try? String(contentsOfFile: "/proc/self/status", encoding: .utf8) else { return nil }
        return peakResident(fromStatus: status)
    }

    /// Parses the `VmHWM:   1234 kB` line of a /proc/<pid>/status text into bytes.
    static func peakResident(fromStatus status: String) -> UInt64? {
        for line in status.split(separator: "\n") where line.hasPrefix("VmHWM:") {
            let fields = line.dropFirst("VmHWM:".count).split(whereSeparator: \.isWhitespace)
            guard let kib = fields.first.flatMap({ UInt64($0) }), fields.dropFirst().first == "kB" else { return nil }
            return kib * 1024
        }
        return nil
    }
}
