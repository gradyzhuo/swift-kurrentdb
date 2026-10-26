import Foundation
import KurrentDB
import LiveBenchCore

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

/// Samples the server's pinned cores, its disk and the `$by_category` backlog over one trial's measure window.
///
/// `stop` returns nil when the headroom could not be measured (no `/proc`, as on macOS, a core or the device missing
/// from it, fewer than two readings, or the projection unreadable). That is not the same as saturation, where
/// `hasHeadroom` is false; callers record "unavailable" for nil.
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

    /// `device` is the block device (or partition) backing the Docker data directory; see `Budget` for how to find it.
    init(cores: [Int], device: String, client: KurrentDBClient, interval: Duration = .seconds(1)) {
        self.init(
            cores: cores, device: device, interval: interval,
            readProcStat: { try? String(contentsOfFile: "/proc/stat", encoding: .utf8) },
            readDiskStats: { try? String(contentsOfFile: "/proc/diskstats", encoding: .utf8) },
            readBuffered: { try? await client.projections(system: .byCategory).detail()?.bufferedEvents }
        )
    }

    /// Everything injectable, for tests. A nil `interval` runs no loop: call `sample()` by hand.
    init(
        cores: [Int], device: String, interval: Duration?,
        readProcStat: @escaping @Sendable () async -> String?,
        readDiskStats: @escaping @Sendable () async -> String?,
        readBuffered: @escaping @Sendable () async -> Int64?,
        wallClockMillis: @escaping @Sendable () -> Double = Monitor.monotonicMillis
    ) {
        self.cores = cores
        self.device = device
        self.interval = interval
        self.readProcStat = readProcStat
        self.readDiskStats = readDiskStats
        self.readBuffered = readBuffered
        self.wallClockMillis = wallClockMillis
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

    /// Baseline reading and starting projection backlog, without the sampling loop.
    func begin() async {
        bufferedStart = await readBuffered()
        previous = await reading()
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

    /// Final reading and projection backlog. `eventsWritten` is what the caller's driver wrote in the window (for the
    /// buffered-growth allowance). Nil when headroom could not be measured (see the type's documentation).
    func stop(eventsWritten: Int64) async -> HeadroomSample? {
        loop?.cancel()
        await loop?.value
        loop = nil
        await sample()
        let bufferedEnd = await readBuffered()
        defer { reset() }
        guard intervals > 0, wall > 0, let bufferedStart, let bufferedEnd else { return nil }
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
            eventsWritten: eventsWritten
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
