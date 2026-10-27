import Foundation
import LiveBenchCore
#if canImport(Glibc)
import Glibc
#endif

/// Per-core CPU counters from `/proc/stat`.
struct ProcStat {
    /// `cpuN` lines only (the aggregate `cpu` line is skipped). Columns: user nice system idle iowait irq softirq
    /// steal guest guest_nice. `total` is the first eight (guest time is already counted inside user and nice) and
    /// `busy` is `total - idle - iowait`. Malformed lines are skipped.
    static func parse(_ text: String) -> [Int: (busy: UInt64, total: UInt64)] {
        var cores: [Int: (busy: UInt64, total: UInt64)] = [:]
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard let name = fields.first, name.hasPrefix("cpu"), let core = Int(name.dropFirst(3)), fields.count >= 9 else { continue }
            let values = fields[1...8].compactMap { UInt64($0) }
            guard values.count == 8 else { continue }
            let total = values.reduce(0, +)
            let idle = values[3] + values[4]
            cores[core] = (busy: total - min(idle, total), total: total)
        }
        return cores
    }
}

/// Block-device counters from `/proc/diskstats`.
struct DiskStats {
    /// The line of `device` with, in the kernel's numbering of `Documentation/admin-guide/iostats.rst` (which counts
    /// the three leading columns major, minor and name as 1-3):
    ///
    ///     field 4  reads completed        field 8   writes completed
    ///     field 7  ms spent reading       field 11  ms spent writing
    ///     field 14 weighted ms doing I/O  (time in queue; its growth over wall time is the mean queue depth)
    ///
    /// `ios` = fields 4 + 8, `ticksMillis` = fields 7 + 11. Merged counts, sectors and the in-flight gauge are not used.
    /// Returns nil when the device is absent or the line is too short (kernels before 4.18 lack nothing used here).
    static func parse(_ text: String, device: String) -> (ios: UInt64, ticksMillis: UInt64, weightedMillis: UInt64)? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 14, fields[2] == device else { continue }
            guard let reads = UInt64(fields[3]), let readMs = UInt64(fields[6]),
                  let writes = UInt64(fields[7]), let writeMs = UInt64(fields[10]),
                  let weighted = UInt64(fields[13])
            else { return nil }
            return (ios: reads + writes, ticksMillis: readMs + writeMs, weightedMillis: weighted)
        }
        return nil
    }
}

/// The block device the monitor reads in `/proc/diskstats`, found by device number. A file system's name is no help:
/// `df` names the root file system of a GitHub-hosted runner `/dev/root`, which `/proc/diskstats` does not list, but
/// `stat`'s `st_dev` (major:minor) is the line's first two columns. The partition's own line is used (the kernel keeps
/// every counter the monitor reads for partitions too), so the figures are those of the file system holding the data.
enum DiskDevice {
    struct Number: Equatable, Sendable {
        var major: UInt64
        var minor: UInt64
    }

    /// Linux `dev_t` → major:minor (glibc's `gnu_dev_major`/`gnu_dev_minor`: minor in bits 0-7 and 20-43, major in
    /// bits 8-19 and 44-63).
    static func split(_ dev: UInt64) -> Number {
        Number(major: ((dev >> 8) & 0xfff) | ((dev >> 32) & 0xffff_f000), minor: (dev & 0xff) | ((dev >> 12) & 0xffff_ff00))
    }

    /// The name of the `/proc/diskstats` line with this major and minor; nil when there is none.
    static func name(of number: Number, diskStats text: String) -> String? {
        for line in text.split(separator: "\n") {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, UInt64(fields[0]) == number.major, UInt64(fields[1]) == number.minor else { continue }
            return String(fields[2])
        }
        return nil
    }

    /// The device holding `directory` (created if missing), resolved through `/proc/diskstats`. Linux only; nil elsewhere
    /// or when it cannot be resolved.
    static func holding(_ directory: URL) -> String? {
        #if os(Linux)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var info = stat()
        guard stat(directory.path, &info) == 0, let text = try? String(contentsOfFile: "/proc/diskstats", encoding: .utf8) else { return nil }
        return name(of: split(UInt64(info.st_dev)), diskStats: text)
        #else
        return nil
        #endif
    }
}

/// Why the monitor cannot measure on this machine (`Monitor.checkReadable`).
struct MonitorError: Error, CustomStringConvertible {
    var description: String
}

/// `$by_category`'s progress after a measure window (`Monitor`'s `readProjectionCatchUp`).
enum ProjectionCatchUp: Sendable, Equatable {
    /// It had processed the last event written by the window's end this many seconds after it.
    case caughtUp(seconds: Double)
    /// It had not within the bound.
    case notCaughtUp
    /// Its position (or the log's) could not be read: no measurement.
    case unreadable
}

/// Samples the server's pinned cores, its disk and the `$by_category` projection over one trial's measure window.
///
/// `stop` returns nil when the headroom could not be measured (no `/proc`, as on macOS, a core or the device missing
/// from it, fewer than two readings, or the projection unreadable). That is not the same as saturation, where
/// `hasHeadroom` is false; callers record "unavailable" for nil. After the window `stop` also waits (up to
/// `EvaluationThresholds.maxProjectionCatchUpSeconds`) for `$by_category` to process the last event written by then.
///
/// Every `interval` the counters are read and the deltas of that interval are added up; an interval in which any
/// counter went backwards (reset, device re-plugged) is dropped. Core busy is Σ Δbusy / Σ Δtotal, disk await is
/// Σ Δ(read ms + write ms) / Σ Δ(reads + writes) (0 when the disk did nothing), queue depth is Σ Δweighted ms / Σ Δwall ms.
actor Monitor {
    private let cores: [Int]
    private let device: String
    private let interval: Duration?
    private let readProcStat: @Sendable () async -> String?
    private let readDiskStats: @Sendable () async -> String?
    private let readBuffered: @Sendable () async -> Int64?
    private let readProjectionCatchUp: @Sendable (_ bound: Duration) async -> ProjectionCatchUp
    private let wallClockMillis: @Sendable () -> Double

    private struct Reading {
        var cpu: [Int: (busy: UInt64, total: UInt64)]
        var disk: (ios: UInt64, ticksMillis: UInt64, weightedMillis: UInt64)
        var wallMillis: Double
    }

    private var previous: Reading?
    private var busy: [Int: UInt64] = [:]
    private var total: [Int: UInt64] = [:]
    private var ios: UInt64 = 0
    private var ticks: UInt64 = 0
    private var weighted: UInt64 = 0
    private var wall: Double = 0
    private var intervals = 0
    private var bufferedStart: Int64?
    private var loop: Task<Void, Never>?

    /// `device` is the `/proc/diskstats` name of the device holding the server's data (`DiskDevice.holding`);
    /// `readBuffered` reads `$by_category`'s `bufferedEvents`, `readProjectionCatchUp` waits up to its bound for the
    /// projection to process the last event written so far. A nil `interval` runs no loop: call `sample()` by hand.
    init(
        cores: [Int], device: String, interval: Duration?,
        readProcStat: @escaping @Sendable () async -> String?,
        readDiskStats: @escaping @Sendable () async -> String?,
        readBuffered: @escaping @Sendable () async -> Int64?,
        readProjectionCatchUp: @escaping @Sendable (_ bound: Duration) async -> ProjectionCatchUp,
        wallClockMillis: @escaping @Sendable () -> Double = Monitor.monotonicMillis
    ) {
        self.cores = cores
        self.device = device
        self.interval = interval
        self.readProcStat = readProcStat
        self.readDiskStats = readDiskStats
        self.readBuffered = readBuffered
        self.readProjectionCatchUp = readProjectionCatchUp
        self.wallClockMillis = wallClockMillis
    }

    /// Fails unless one reading has every pinned core in `/proc/stat` and the device in `/proc/diskstats`: run at cell
    /// start on Linux, where a monitor that can never measure would leave every step without a comparison.
    func checkReadable() async throws {
        guard let statText = await readProcStat() else { throw MonitorError(description: "/proc/stat is unreadable") }
        guard let diskText = await readDiskStats() else { throw MonitorError(description: "/proc/diskstats is unreadable") }
        let cpu = ProcStat.parse(statText)
        let missing = cores.filter { cpu[$0] == nil }
        guard missing.isEmpty else {
            throw MonitorError(description: "/proc/stat has no line for server core(s) \(missing.map(String.init).joined(separator: ", "))")
        }
        guard DiskStats.parse(diskText, device: device) != nil else {
            throw MonitorError(description: "/proc/diskstats has no readable line for device '\(device)'")
        }
    }

    static let monotonicMillis: @Sendable () -> Double = {
        Double(DispatchTime.now().uptimeNanoseconds) / 1_000_000
    }

    /// Takes the baseline reading and the projection's starting backlog, then samples every `interval`. A second
    /// call without `stop` replaces the running window (its sampler is stopped and its totals discarded), so there is
    /// never more than one sampler.
    func start() async {
        if let running = loop {
            running.cancel()
            await running.value
            loop = nil
        }
        reset()
        await begin()
        guard let interval else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                if Task.isCancelled { break }
                await self?.sample()
            }
        }
    }

    /// Baseline reading and starting projection backlog, without the sampling loop. The reading comes first so a slow
    /// statistics query cannot move the start of the sampled window.
    func begin() async {
        previous = await reading()
        bufferedStart = await readBuffered()
    }

    /// One reading, folded into the running totals against the previous one.
    func sample() async {
        guard let current = await reading() else { return }
        defer { previous = current }
        guard let last = previous else { return }
        let elapsed = current.wallMillis - last.wallMillis
        guard elapsed > 0, current.disk.ios >= last.disk.ios, current.disk.ticksMillis >= last.disk.ticksMillis,
              current.disk.weightedMillis >= last.disk.weightedMillis
        else { return }
        var busyDeltas: [Int: UInt64] = [:]
        var totalDeltas: [Int: UInt64] = [:]
        for core in cores {
            guard let now = current.cpu[core], let before = last.cpu[core], now.busy >= before.busy, now.total >= before.total else { return }
            busyDeltas[core] = now.busy - before.busy
            totalDeltas[core] = now.total - before.total
        }
        for core in cores {
            busy[core, default: 0] += busyDeltas[core] ?? 0
            total[core, default: 0] += totalDeltas[core] ?? 0
        }
        ios += current.disk.ios - last.disk.ios
        ticks += current.disk.ticksMillis - last.disk.ticksMillis
        weighted += current.disk.weightedMillis - last.disk.weightedMillis
        wall += elapsed
        intervals += 1
    }

    /// Final reading, then the projection's catch-up to the last event written by now. `eventsWritten` is what the
    /// caller's driver wrote in the window (recorded with the sample). Nil when headroom could not be measured (see the
    /// type's documentation).
    ///
    /// The catch-up wait starts first, at the window's end, and runs alongside the final reading and the statistics
    /// query, so neither can delay its clock and hide a slow projection.
    func stop(eventsWritten: Int64) async -> HeadroomSample? {
        let readProjectionCatchUp = readProjectionCatchUp
        async let catchUpResult = readProjectionCatchUp(.seconds(EvaluationThresholds.maxProjectionCatchUpSeconds))
        loop?.cancel()
        await loop?.value
        loop = nil
        await sample()
        let bufferedEnd = await readBuffered()
        let catchUp = await catchUpResult
        defer { reset() }
        guard intervals > 0, wall > 0, let bufferedStart, let bufferedEnd, catchUp != .unreadable else { return nil }
        var coreBusy: [Double] = []
        for core in cores {
            guard let t = total[core], t > 0 else { return nil }
            coreBusy.append(Double(busy[core] ?? 0) / Double(t))
        }
        return HeadroomSample(
            coreBusy: coreBusy,
            diskAwaitMillis: ios > 0 ? Double(ticks) / Double(ios) : 0,
            diskQueueDepth: Double(weighted) / wall,
            projectionBufferedStart: bufferedStart,
            projectionBufferedEnd: bufferedEnd,
            eventsWritten: eventsWritten,
            projectionCatchUpSeconds: { if case let .caughtUp(seconds) = catchUp { seconds } else { nil } }()
        )
    }

    private func reading() async -> Reading? {
        guard let statText = await readProcStat(), let diskText = await readDiskStats() else { return nil }
        let cpu = ProcStat.parse(statText)
        guard !cpu.isEmpty, let disk = DiskStats.parse(diskText, device: device) else { return nil }
        return Reading(cpu: cpu, disk: disk, wallMillis: wallClockMillis())
    }

    private func reset() {
        previous = nil
        busy = [:]
        total = [:]
        ios = 0
        ticks = 0
        weighted = 0
        wall = 0
        intervals = 0
        bufferedStart = nil
    }
}
