import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator
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
            readBuffered: { 0 }
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

    init(stats: [String], disks: [String], buffered: [Int64], wallMillis: [Double]) {
        self.stats = stats
        self.disks = disks
        self.buffered = buffered
        self.wallMillis = wallMillis
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
            wallClockMillis: { self.next(self.wallMillis, &self.wallIndex) ?? 0 }
        )
    }
}
