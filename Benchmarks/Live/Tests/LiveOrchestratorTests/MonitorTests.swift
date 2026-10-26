import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Synchronization
import Testing

/// `/proc` fixtures for the headroom monitor. Columns of a `cpuN` line: user nice system idle iowait irq softirq steal guest guest_nice.
private func procStat(core0: (busy: Int, idle: Int), core1: (busy: Int, idle: Int)) -> String {
    """
    cpu  \(core0.busy + core1.busy) 0 0 \(core0.idle + core1.idle) 0 0 0 0 0 0
    cpu0 \(core0.busy) 0 0 \(core0.idle) 0 0 0 0 0 0
    cpu1 \(core1.busy) 0 0 \(core1.idle) 0 0 0 0 0 0
    intr 12345
    ctxt 99
    """
}

/// One `/proc/diskstats` line for `sda`: reads/ms-reading and writes/ms-writing and weighted ms, other fields zero or dummy.
private func diskStats(reads: Int, readMs: Int, writes: Int, writeMs: Int, weightedMs: Int) -> String {
    """
       7       0 loop0 1 0 2 3 0 0 0 0 0 0 0
       8       0 sda \(reads) 5 800 \(readMs) \(writes) 6 900 \(writeMs) 0 77 \(weightedMs) 0 0 0 0 0
       8       1 sda1 9 9 9 9 9 9 9 9 9 9 9
    """
}

@Suite("Headroom monitor")
struct MonitorTests {
    @Test func procStatParsesEveryCoreAndSkipsTheAggregateLine() {
        let parsed = ProcStat.parse(procStat(core0: (busy: 90, idle: 10), core1: (busy: 20, idle: 80)))
        #expect(parsed.keys.sorted() == [0, 1])
        #expect(parsed[0]?.busy == 90 && parsed[0]?.total == 100)
        #expect(parsed[1]?.busy == 20 && parsed[1]?.total == 100)
    }

    @Test func procStatCountsIowaitAsIdleAndSkipsGuestTime() {
        // user=10 nice=5 system=5 idle=60 iowait=10 irq=2 softirq=3 steal=5 guest=7 guest_nice=3
        let parsed = ProcStat.parse("cpu3 10 5 5 60 10 2 3 5 7 3\n")
        #expect(parsed[3]?.total == 100) // guest columns are already inside user/nice
        #expect(parsed[3]?.busy == 30) // everything except idle and iowait
    }

    @Test func procStatToleratesGarbage() {
        #expect(ProcStat.parse("").isEmpty)
        #expect(ProcStat.parse("cpu0 1 2\ncpuX 1 2 3 4 5 6 7 8\nnonsense").isEmpty)
    }

    @Test func diskStatsPicksTheDeviceAndSumsTheRightFields() {
        let parsed = DiskStats.parse(diskStats(reads: 100, readMs: 200, writes: 300, writeMs: 400, weightedMs: 1234), device: "sda")
        #expect(parsed?.ios == 400)
        #expect(parsed?.ticksMillis == 600)
        #expect(parsed?.weightedMillis == 1234)
        #expect(DiskStats.parse(diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1), device: "nvme0n1") == nil)
        #expect(DiskStats.parse("8 0 sda 1 2 3", device: "sda") == nil) // too few columns
    }

    @Test func perCoreBusyFromTwoSnapshots() async {
        let script = Script(
            stats: [procStat(core0: (busy: 1000, idle: 1000), core1: (busy: 500, idle: 1500)),
                    procStat(core0: (busy: 1090, idle: 1010), core1: (busy: 520, idle: 1580))],
            disks: [diskStats(reads: 0, readMs: 0, writes: 0, writeMs: 0, weightedMs: 0),
                    diskStats(reads: 0, readMs: 0, writes: 0, writeMs: 0, weightedMs: 0)],
            buffered: [10, 10], wallMillis: [0, 1000]
        )
        let monitor = script.monitor(cores: [0, 1])
        await monitor.begin()
        await monitor.sample()
        let sample = await monitor.stop(eventsWritten: 0)
        #expect(sample != nil)
        #expect(abs((sample?.coreBusy[0] ?? 0) - 0.90) < 1e-9)
        #expect(abs((sample?.coreBusy[1] ?? 0) - 0.20) < 1e-9)
    }

    @Test func diskAwaitAndQueue() async {
        // 1000 I/Os (400 reads, 600 writes) took 4000 ms in total; weighted time grew 500 ms over 1000 ms wall.
        let script = Script(
            stats: [procStat(core0: (busy: 0, idle: 100), core1: (busy: 0, idle: 100)), procStat(core0: (busy: 0, idle: 200), core1: (busy: 0, idle: 200))],
            disks: [diskStats(reads: 100, readMs: 100, writes: 200, writeMs: 300, weightedMs: 7000),
                    diskStats(reads: 500, readMs: 1700, writes: 800, writeMs: 2700, weightedMs: 7500)],
            buffered: [0, 0], wallMillis: [0, 1000]
        )
        let monitor = script.monitor(cores: [0])
        await monitor.begin()
        await monitor.sample()
        let sample = await monitor.stop(eventsWritten: 0)
        #expect(abs((sample?.diskAwaitMillis ?? -1) - 4.0) < 1e-9)
        #expect(abs((sample?.diskQueueDepth ?? -1) - 0.5) < 1e-9)
    }

    @Test func idleDiskHasZeroAwaitNotNaN() async {
        let line = diskStats(reads: 5, readMs: 5, writes: 5, writeMs: 5, weightedMs: 5)
        let script = Script(
            stats: [procStat(core0: (busy: 0, idle: 100), core1: (busy: 0, idle: 100)), procStat(core0: (busy: 0, idle: 200), core1: (busy: 0, idle: 200))],
            disks: [line, line], buffered: [0, 0], wallMillis: [0, 1000]
        )
        let monitor = script.monitor(cores: [0])
        await monitor.begin()
        await monitor.sample()
        let sample = await monitor.stop(eventsWritten: 0)
        #expect(sample?.diskAwaitMillis == 0 && sample?.diskQueueDepth == 0)
    }

    @Test func projectionBufferedAndEventsWrittenAreCarriedThrough() async {
        let script = Script(
            stats: [procStat(core0: (busy: 0, idle: 0), core1: (busy: 0, idle: 0)), procStat(core0: (busy: 1, idle: 9), core1: (busy: 0, idle: 10))],
            disks: Array(repeating: diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1), count: 2),
            buffered: [40, 95], wallMillis: [0, 1000]
        )
        let monitor = script.monitor(cores: [0, 1])
        await monitor.begin()
        await monitor.sample()
        let sample = await monitor.stop(eventsWritten: 12_345)
        #expect(sample?.projectionBufferedStart == 40)
        #expect(sample?.projectionBufferedEnd == 95)
        #expect(sample?.eventsWritten == 12_345)
        #expect(sample.map(hasHeadroom) == true)
    }

    @Test func projectionCatchUpAfterTheWindowIsCarriedThroughAndGated() async {
        let stats = [procStat(core0: (busy: 0, idle: 0), core1: (busy: 0, idle: 0)), procStat(core0: (busy: 1, idle: 9), core1: (busy: 0, idle: 10))]
        let disks = Array(repeating: diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1), count: 2)
        func stopped(_ catchUp: ProjectionCatchUp) async -> HeadroomSample? {
            let monitor = Script(stats: stats, disks: disks, buffered: [0, 0], wallMillis: [0, 1000], catchUp: catchUp).monitor(cores: [0, 1])
            await monitor.begin()
            await monitor.sample()
            return await monitor.stop(eventsWritten: 100)
        }
        let quick = await stopped(.caughtUp(seconds: 1.25))
        #expect(quick?.projectionCatchUpSeconds == 1.25)
        #expect(quick.map(hasHeadroom) == true)
        let behind = await stopped(.notCaughtUp)
        #expect(behind != nil && behind?.projectionCatchUpSeconds == nil)
        #expect(behind.map(hasHeadroom) == false)
        // Unreadable is not saturation: no sample, so "headroom unavailable".
        #expect(await stopped(.unreadable) == nil)
    }

    @Test func projectionCatchUpGetsTheGatesBound() async {
        let bound = Mutex<Duration?>(nil)
        let monitor = Monitor(
            cores: [0], device: "sda", interval: nil,
            readProcStat: { procStat(core0: (busy: 1, idle: 1), core1: (busy: 1, idle: 1)) },
            readDiskStats: { diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1) },
            readBuffered: { 0 },
            readProjectionCatchUp: { limit in bound.withLock { $0 = limit }; return .caughtUp(seconds: 0) },
            wallClockMillis: { 0 }
        )
        await monitor.begin()
        _ = await monitor.stop(eventsWritten: 0)
        #expect(bound.withLock { $0 } == .seconds(EvaluationThresholds.maxProjectionCatchUpSeconds))
    }

    @Test func readabilityCheckNamesWhatIsMissing() async throws {
        let stats = procStat(core0: (busy: 1, idle: 1), core1: (busy: 1, idle: 1))
        let disk = diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1)
        try await Script(stats: [stats], disks: [disk], buffered: [0], wallMillis: [0]).monitor(cores: [0, 1]).checkReadable()
        await #expect(throws: MonitorError.self) {
            try await Script(stats: [stats], disks: [disk], buffered: [0], wallMillis: [0]).monitor(cores: [0, 1], device: "root").checkReadable()
        }
        await #expect(throws: MonitorError.self) {
            try await Script(stats: [stats], disks: [disk], buffered: [0], wallMillis: [0]).monitor(cores: [0, 5]).checkReadable()
        }
        await #expect(throws: MonitorError.self) {
            try await Script(stats: [], disks: [], buffered: [0], wallMillis: [0]).monitor(cores: [0]).checkReadable()
        }
    }

    @Test func intervalsWithResetCountersAreSkipped() async {
        // The second snapshot is lower than the first (counter reset); only the third interval counts.
        let script = Script(
            stats: [procStat(core0: (busy: 500, idle: 500), core1: (busy: 0, idle: 1000)),
                    procStat(core0: (busy: 10, idle: 10), core1: (busy: 0, idle: 20)),
                    procStat(core0: (busy: 20, idle: 20), core1: (busy: 0, idle: 30))],
            disks: Array(repeating: diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1), count: 3),
            buffered: [0, 0], wallMillis: [0, 1000, 2000]
        )
        let monitor = script.monitor(cores: [0, 1])
        await monitor.begin()
        await monitor.sample()
        await monitor.sample()
        let sample = await monitor.stop(eventsWritten: 0)
        #expect(abs((sample?.coreBusy[0] ?? 0) - 0.5) < 1e-9)
    }

    @Test func unavailableProcFilesMeanNoSampleNotSaturation() async {
        let script = Script(stats: [], disks: [], buffered: [0, 0], wallMillis: [0, 1000])
        let monitor = script.monitor(cores: [0, 1])
        await monitor.begin()
        await monitor.sample()
        #expect(await monitor.stop(eventsWritten: 0) == nil)
    }

    @Test func aMissingCoreOrDeviceMeansNoSample() async {
        let stats = procStat(core0: (busy: 1, idle: 1), core1: (busy: 1, idle: 1))
        let disk = diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1)
        let noCore = Script(stats: [stats, stats], disks: [disk, disk], buffered: [0, 0], wallMillis: [0, 1000])
        let a = noCore.monitor(cores: [0, 7])
        await a.begin(); await a.sample()
        #expect(await a.stop(eventsWritten: 0) == nil)
        let noDevice = Script(stats: [stats, stats], disks: [disk, disk], buffered: [0, 0], wallMillis: [0, 1000])
        let b = noDevice.monitor(cores: [0], device: "nvme9n9")
        await b.begin(); await b.sample()
        #expect(await b.stop(eventsWritten: 0) == nil)
    }

    @Test func unreadableProjectionMeansNoSample() async {
        let stats = procStat(core0: (busy: 1, idle: 1), core1: (busy: 1, idle: 1))
        let disk = diskStats(reads: 1, readMs: 1, writes: 1, writeMs: 1, weightedMs: 1)
        let script = Script(stats: [stats, stats], disks: [disk, disk], buffered: [], wallMillis: [0, 1000])
        let monitor = script.monitor(cores: [0])
        await monitor.begin(); await monitor.sample()
        #expect(await monitor.stop(eventsWritten: 0) == nil)
    }

    @Test func samplingLoopRunsAndStopsOnItsOwn() async {
        // Real timers, tiny interval: whatever the loop captured, stop() must return a sample from constant fixtures.
        let counter = Counter()
        let monitor = Monitor(
            cores: [0], device: "sda", interval: .milliseconds(5),
            readProcStat: { await counter.tick(); return procStat(core0: (busy: await counter.value * 9, idle: await counter.value), core1: (busy: 0, idle: 1)) },
            readDiskStats: { diskStats(reads: await counter.value, readMs: 0, writes: 0, writeMs: 0, weightedMs: 0) },
            readBuffered: { 0 },
            readProjectionCatchUp: { _ in .caughtUp(seconds: 0) }
        )
        await monitor.start()
        try? await Task.sleep(for: .milliseconds(100))
        let sample = await monitor.stop(eventsWritten: 1)
        #expect(sample != nil)
        #expect(abs((sample?.coreBusy[0] ?? 0) - 0.9) < 1e-9)
    }
}

private actor Counter {
    var value = 0
    func tick() { value += 1 }
}

/// Hands out scripted `/proc` texts, projection readings and wall times, one per call (the last repeats once exhausted).
private final class Script: @unchecked Sendable {
    private let lock = NSLock()
    private let stats: [String]
    private let disks: [String]
    private let buffered: [Int64]
    private let wallMillis: [Double]
    private var statIndex = 0, diskIndex = 0, bufferedIndex = 0, wallIndex = 0

    private let catchUp: ProjectionCatchUp

    init(stats: [String], disks: [String], buffered: [Int64], wallMillis: [Double], catchUp: ProjectionCatchUp = .caughtUp(seconds: 0.3)) {
        self.stats = stats
        self.disks = disks
        self.buffered = buffered
        self.wallMillis = wallMillis
        self.catchUp = catchUp
    }

    private func next<T>(_ items: [T], _ index: inout Int) -> T? {
        lock.lock()
        defer { lock.unlock() }
        guard !items.isEmpty else { return nil }
        defer { index += 1 }
        return items[min(index, items.count - 1)]
    }

    func monitor(cores: [Int], device: String = "sda") -> Monitor {
        Monitor(
            cores: cores, device: device, interval: nil,
            readProcStat: { self.next(self.stats, &self.statIndex) },
            readDiskStats: { self.next(self.disks, &self.diskIndex) },
            readBuffered: { self.next(self.buffered, &self.bufferedIndex) },
            readProjectionCatchUp: { _ in self.catchUp },
            wallClockMillis: { self.next(self.wallMillis, &self.wallIndex) ?? 0 }
        )
    }
}

@Suite("Headroom monitor restarts")
struct MonitorRestartTests {
    @Test func startingTwiceKeepsOneSampler() async {
        final class Reads: Sendable { let count = Mutex(0) }
        func counted(_ reads: Reads) -> Monitor {
            Monitor(
                cores: [0], device: "sda", interval: .milliseconds(20),
                readProcStat: { reads.count.withLock { $0 += 1 }; return "cpu0 1 0 0 1 0 0 0 0 0 0\n" },
                readDiskStats: { "   8       0 sda 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0\n" },
                readBuffered: { 0 },
                readProjectionCatchUp: { _ in .caughtUp(seconds: 0) }
            )
        }
        let once = Reads(), twice = Reads()
        let single = counted(once), double = counted(twice)
        await single.start()
        await double.start()
        await double.start()
        try? await Task.sleep(for: .milliseconds(500))
        _ = await single.stop(eventsWritten: 0)
        _ = await double.stop(eventsWritten: 0)
        // Same window and interval: a second sampler would read about twice as often as the single one.
        let (a, b) = (once.count.withLock { $0 }, twice.count.withLock { $0 })
        #expect(Double(b) < 1.5 * Double(a), "single start read \(a) times, double start \(b)")
    }
}

/// `/proc/diskstats` of a GitHub-hosted Ubuntu runner (`/` is `/dev/root`, the alias of `sda1`; `/mnt` is `sdb1`),
/// plus an NVMe disk and a device-mapper volume.
private let runnerDiskStats = """
   7       0 loop0 52 0 2290 12 0 0 0 0 0 28 12 0 0 0 0 0 0
   8       0 sda 21430 6390 1859674 7211 51740 41617 4198136 49011 0 51068 56223 0 0 0 0 0 0
   8       1 sda1 21216 6390 1849186 7171 51740 41617 4198136 49011 0 50984 56182 0 0 0 0 0 0
   8      14 sda14 69 0 552 9 0 0 0 0 0 20 9 0 0 0 0 0 0
   8      15 sda15 92 0 6324 24 1 0 1 0 0 40 24 0 0 0 0 0 0
   8      16 sdb 1029 4211 66574 523 50 13 4544 172 0 676 696 0 0 0 0 0 0
   8      17 sdb1 948 4211 61722 487 50 13 4544 172 0 588 659 0 0 0 0 0 0
 259       0 nvme0n1 100 0 800 10 10 0 80 1 0 12 11 0 0 0 0 0 0
 259       1 nvme0n1p1 90 0 720 9 10 0 80 1 0 11 10 0 0 0 0 0 0
 253       0 dm-0 5 0 40 1 0 0 0 0 0 1 1 0 0 0 0 0 0
"""

@Suite("Disk device resolution")
struct DiskDeviceTests {
    /// glibc's `makedev`: minor low byte | major << 8 (12 bits) | minor high bits << 12 | major high bits << 32.
    private func makedev(_ major: UInt64, _ minor: UInt64) -> UInt64 {
        (minor & 0xff) | ((major & 0xfff) << 8) | ((minor & 0xffff_ff00) << 12) | ((major & 0xffff_f000) << 32)
    }

    @Test func deviceNumberSplitsIntoMajorAndMinor() {
        #expect(DiskDevice.split(makedev(8, 1)) == DiskDevice.Number(major: 8, minor: 1))
        #expect(DiskDevice.split(makedev(259, 1)) == DiskDevice.Number(major: 259, minor: 1))
        #expect(DiskDevice.split(makedev(8, 300)) == DiskDevice.Number(major: 8, minor: 300))
        #expect(DiskDevice.split(makedev(4100, 70_000)) == DiskDevice.Number(major: 4100, minor: 70_000))
    }

    /// `/dev/root` (what `df` names the root file system on a runner) is not in `/proc/diskstats`; its device number is.
    @Test func rootFileSystemResolvesByDeviceNumberNotByName() {
        #expect(DiskDevice.name(of: .init(major: 8, minor: 1), diskStats: runnerDiskStats) == "sda1")
        #expect(DiskDevice.name(of: .init(major: 8, minor: 17), diskStats: runnerDiskStats) == "sdb1")
        #expect(DiskDevice.name(of: .init(major: 259, minor: 1), diskStats: runnerDiskStats) == "nvme0n1p1")
        #expect(DiskDevice.name(of: .init(major: 253, minor: 0), diskStats: runnerDiskStats) == "dm-0")
        // The resolved line is one the monitor can read.
        let reads: UInt64 = 21216, writes: UInt64 = 51740
        let ios = DiskStats.parse(runnerDiskStats, device: "sda1")?.ios
        #expect(ios == reads + writes)
    }

    @Test func unknownDeviceNumbersDoNotResolve() {
        // Major 0 is an anonymous device (overlayfs, tmpfs, btrfs subvolumes): no block device to monitor.
        #expect(DiskDevice.name(of: .init(major: 0, minor: 42), diskStats: runnerDiskStats) == nil)
        #expect(DiskDevice.name(of: .init(major: 8, minor: 2), diskStats: runnerDiskStats) == nil)
        #expect(DiskDevice.name(of: .init(major: 8, minor: 1), diskStats: "") == nil)
        #expect(DiskDevice.name(of: .init(major: 8, minor: 1), diskStats: "8 1\nnonsense") == nil)
    }
}
