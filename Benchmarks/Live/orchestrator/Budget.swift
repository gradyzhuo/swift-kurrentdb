import Foundation
import LiveBenchCore

/// What to do about a cell's disk needs on this runner.
enum BudgetDecision: Equatable, Sendable {
    case ok
    /// Seed this many catch-up events instead of `Seeder.catchUpEvents`; the orchestrator records `corpusReducedTo`.
    case reduceCorpus(to: Int)
    case refuse(reason: String)
}

/// Per-cell disk and time estimates, from the fixed parameters in `config/` and the Seeder's data volumes.
///
/// Disk. Per-event bytes on disk are `data + metadata + perEventOverheadBytes`. The overhead was measured on
/// `kurrentplatform/kurrentdb:26.2.3` (catch-up seeding through `Seeder`, server stopped, `writer.chk` read from the
/// data directory, which is the number of log bytes written, `$ce-` link events and projection checkpoints included):
///
///     300 B data + 60 B metadata, 200,000 events: 182,293,147 B of log = 911 B per event  -> overhead 551 B
///     4096 B data + 60 B metadata, 100,000 events: 471,610,952 B of log = 4,716 B per event -> overhead 560 B
///
/// The log overhead (record header, stream name, event type, the `$ce` link event) is a constant of about 555 B. The
/// index grows with the event count too (two entries per event, the event and its link); 85 B per event are added for
/// it, which with rounding gives the documented 640 B. The 256 MiB chunk preallocation and the index's own base
/// size (about 83 MB at 100,000 to 200,000 events; it did not grow visibly between those) are the fixed part,
/// `databaseFixedBytes`.
///
/// A snapshot is a full copy of the seeded data directory, so a seeded cell needs twice the seed size, plus the
/// largest trial's own writes, plus `reserveBytes` for Docker, logs, results and the OS.
///
/// Finding the device for `DiskStats`: `df --output=source <docker data dir>` gives a partition such as `/dev/sda1`
/// or `/dev/nvme0n1p1`; the block device under it is `basename $(readlink -f /sys/class/block/<partition>/..)`
/// (`sda`, `nvme0n1`), and `/proc/diskstats` lists both the disk and its partitions. The disk, not the partition, is
/// what the orchestrator passes. (A partition's own line is also valid; the monitor only looks the name up.)
///
/// Time. Per trial: `restoreAndStartSeconds` (restore the snapshot, start the container, wait ready and, for the
/// cells that need it, `$by_category`) + warmup + measure + drain, once per rate, round and client; plus a one-time
/// setup and the seeding.
enum Budget {
    // MARK: - Fixed parameters (the spec's table; the orchestrator builds EffectiveScenarios from the same numbers)

    static let warmupSeconds = 30.0
    static let measureSeconds = 60.0
    static let drainSeconds = 5.0
    static let restoreAndStartSeconds = 20.0
    /// Certificate generation, first start, clean stop and snapshot, once per cell.
    static let oneTimeSetupSeconds = 120.0
    /// Conservative seeding speed in events per second, including the wait for `$by_category` to link everything.
    static let seedEventsPerSecond = 5_000.0
    /// The orchestrator refuses a cell estimated above this (a CI job is limited to 6 h).
    static let jobLimitMinutes = 330.0
    /// No trial starts after this many minutes of job time (the workflow's job timeout is 350): a cell that runs over
    /// its estimate stops with a reason instead of being killed mid-trial.
    static let jobTimeGuardMinutes = 340.0
    /// Events per batch of the append-throughput scenario.
    static let throughputBatchSize = 50
    /// Per-operation deadline and in-flight cap, identical for every client.
    static let deadlineMillis = 5_000
    static let inFlightCap = 256
    /// Streams the append scenarios pick from (uniform, seeded).
    static let appendStreamCount = 100_000
    /// Streams the subscription writers pick from (the catch-up corpus is spread over as many, `Seeder.catchUpStreamCount`).
    static let subscriptionStreamCount = 1_000

    // MARK: - Disk

    static let perEventOverheadBytes: Int64 = 640
    static let databaseFixedBytes: Int64 = 350_000_000
    static let reserveBytes: Int64 = 2_000_000_000
    /// Free space of a GitHub-hosted ubuntu-latest runner after cleanup (about 14 GB).
    static let githubRunnerFreeBytes: Int64 = 14_000_000_000
    /// A catch-up corpus below this is not worth measuring; the cell is refused instead.
    static let minimumCorpusEvents = 10_000
    private static let corpusStep = 1_000

    static func perEventBytes(eventSize: Int) -> Int64 {
        Int64(eventSize + Seeder().metadataSize) + perEventOverheadBytes
    }

    /// Events the seeder writes for `cell` (the catch-up corpus before any reduction).
    static func seedEvents(_ cell: Cell) -> Int {
        switch cell.kind {
        case .appendLatency, .appendThroughput, .persistentSubscription:
            0
        case .rebuild:
            // Measured streams plus as many warmup streams.
            2 * Seeder().rebuildStreamCount * (cell.streamLength ?? 0)
        case .catchUp:
            Seeder().catchUpEvents
        }
    }

    /// Size of the seeded data directory (and so of its snapshot).
    static func seedBytes(_ cell: Cell) -> Int64 {
        seedBytes(cell, events: seedEvents(cell))
    }

    private static func seedBytes(_ cell: Cell, events: Int) -> Int64 {
        databaseFixedBytes + Int64(events) * perEventBytes(eventSize: cell.eventSize)
    }

    /// Bytes the busiest trial writes on top of the restored snapshot: the top rate for the whole trial, in event
    /// units (a throughput cell's rate counts batches). Rebuild trials only read.
    static func trialWriteBytes(_ cell: Cell) -> Int64 {
        trialWriteBytes(cell, rate: cell.rates.max() ?? 0)
    }

    /// Bytes one trial at `rate` writes on top of the restored snapshot (warmup, measure and drain at that rate).
    static func trialWriteBytes(_ cell: Cell, rate: Double) -> Int64 {
        let eventsPerUnit: Double = cell.kind == .appendThroughput ? Double(throughputBatchSize) : 1
        switch cell.kind {
        case .rebuild:
            return 0
        case .appendLatency, .appendThroughput, .persistentSubscription, .catchUp:
            let seconds = warmupSeconds + measureSeconds + drainSeconds
            let events = rate * eventsPerUnit * seconds
            return Int64(events.rounded(.up)) * perEventBytes(eventSize: cell.eventSize)
        }
    }

    /// Free disk a trial at `rate` needs before it starts: its writes plus the reserve. Checked before every trial;
    /// the data directory then still holds the previous trial's writes, which the restore frees, so this errs safe.
    static func stepRequiredBytes(_ cell: Cell, rate: Double) -> Int64 {
        trialWriteBytes(cell, rate: rate) + reserveBytes
    }

    private static func requiredBytes(_ cell: Cell, events: Int) -> Int64 {
        // data dir + snapshot + the trial's writes + reserve
        2 * seedBytes(cell, events: events) + trialWriteBytes(cell) + reserveBytes
    }

    /// Total disk needed for `cell` with its full seed.
    static func requiredBytes(_ cell: Cell) -> Int64 {
        requiredBytes(cell, events: seedEvents(cell))
    }

    static func check(freeBytes: Int64, cell: Cell) -> BudgetDecision {
        let needed = requiredBytes(cell)
        if freeBytes >= needed { return .ok }
        let shortfall = "needs \(needed / 1_000_000) MB (seed, snapshot copy, trial writes, \(reserveBytes / 1_000_000) MB reserve) but \(freeBytes / 1_000_000) MB are free"
        guard cell.kind == .catchUp else {
            return .refuse(reason: "cell \(cell.id) \(shortfall); only the catch-up corpus can shrink")
        }
        let perEvent = perEventBytes(eventSize: cell.eventSize)
        let corpusBudget = (freeBytes - reserveBytes - trialWriteBytes(cell)) / 2 - databaseFixedBytes
        let events = Int(max(0, corpusBudget) / perEvent) / corpusStep * corpusStep
        guard events >= minimumCorpusEvents else {
            return .refuse(reason: "cell \(cell.id) \(shortfall); even a \(minimumCorpusEvents)-event corpus does not fit")
        }
        return .reduceCorpus(to: events)
    }

    // MARK: - Time

    static func trialSeconds() -> Double {
        restoreAndStartSeconds + warmupSeconds + measureSeconds + drainSeconds
    }

    /// Estimated wall minutes for the whole cell: every client runs every rate in every round, plus one-time setup and seeding.
    static func estimatedMinutes(_ cell: Cell, clients: Int) -> Double {
        let trials = Double(cell.rates.count * cell.rounds * max(clients, 0))
        let seeding = Double(seedEvents(cell)) / seedEventsPerSecond
        return (trials * trialSeconds() + oneTimeSetupSeconds + seeding) / 60
    }
}
