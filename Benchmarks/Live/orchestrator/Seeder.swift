import Foundation
import KurrentDB
import LiveBenchCore

/// What the seeder wrote, for building each trial's `EffectiveScenario` and for the pre-trial `$by_category` wait.
struct SeedManifest: Codable, Sendable, Equatable {
    /// Measured rebuild streams (`<category>-<n>`); their warmup twins are `<category>w-<n>`. Empty for other kinds.
    var rebuildStreams: [String]
    /// Category holding the catch-up corpus (`$ce-<category>`), or nil when the cell has none.
    var catchUpCategory: String?
    /// Events in the catch-up corpus (0 when there is none); the scenario's `catchUpExpectedEvents`.
    var catchUpEvents: Int
    /// Log position `(commit, prepare)` of the last event the seeder wrote (0, 0 when it wrote nothing);
    /// `$by_category` must reach it before a trial (`waitForByCategory(client:toReach:prepare:timeout:)`).
    var lastCommitPosition: UInt64
    var lastPreparePosition: UInt64
    /// Set when the catch-up corpus was reduced below `Seeder.catchUpEvents` (disk budget); equals `catchUpEvents`.
    var corpusReducedTo: Int?
}

/// Writes a cell's pre-seeded data with the SDK, once per cell, before the snapshot is taken.
///
/// Naming follows the driver contract: the stream prefix equals `category` and neither contains `-`, so
/// `<category>-<n>` lands in `$ce-<category>` and the warmup streams `<category>w-<n>` in `$ce-<category>w`.
/// Events are `BenchEvent` JSON built by `PayloadFactory` (data `cell.eventSize` bytes, metadata `metadataSize`
/// bytes); event `k` of a rebuild stream `n` of length `L` has index `n * L + k`, catch-up corpus event `k` has index
/// `k` and goes to `<category>-<k % catchUpStreamCount>`. Appends are batched and run concurrently across streams.
///
/// Persistent-subscription groups are created per trial by the trial runner, not here; per-kind seeding lives in
/// `seed(cell:client:)`'s switch, where such a step would go.
struct Seeder: Sendable {
    /// Stream prefix and category of every seeded stream (no `-`).
    var category = "bench"
    var metadataSize = 60
    /// Seeds the payload filler (the drivers validate sizes and counts, not filler bytes).
    var payloadSeed: UInt64 = 42
    /// Streams per rebuild length (and as many warmup streams).
    var rebuildStreamCount = 100
    /// Catch-up corpus size before any budget reduction.
    var catchUpEvents = 1_000_000
    /// Streams the catch-up corpus is spread over (round robin).
    var catchUpStreamCount = 1_000
    /// A smaller corpus chosen by the caller (disk budget); recorded as `corpusReducedTo`.
    var catchUpCorpusOverride: Int?
    /// Events per append, further capped at about 1 MB of payload per append.
    var appendBatchSize = 500
    /// Concurrent streams being appended to.
    var concurrency = 16
    /// Bound on waiting for `$by_category` to process (and, for catch-up, link) everything written.
    var projectionTimeout: Duration = .seconds(1800)

    struct SeedError: Error, CustomStringConvertible {
        let description: String
    }

    /// Enables `$by_category`, writes the data `cell` needs and waits until `$by_category` has processed all of it
    /// (for catch-up, until `$ce-<category>` holds exactly the corpus).
    func seed(cell: Cell, client: KurrentDBClient) async throws -> SeedManifest {
        guard !category.isEmpty, !category.contains("-") else {
            throw SeedError(description: "category '\(category)' must be non-empty and free of '-'")
        }
        try await enableByCategory(client)
        let factory = PayloadFactory(dataSize: cell.eventSize, metadataSize: metadataSize, seed: payloadSeed)
        var manifest = SeedManifest(rebuildStreams: [], catchUpCategory: nil, catchUpEvents: 0, lastCommitPosition: 0, lastPreparePosition: 0, corpusReducedTo: nil)

        switch cell.kind {
        case .appendLatency, .appendThroughput, .persistentSubscription:
            break

        case .rebuild:
            guard let length = cell.streamLength, length > 0 else {
                throw SeedError(description: "rebuild cell \(cell.id) needs a positive streamLength")
            }
            let measured = (0..<rebuildStreamCount).map { "\(category)-\($0)" }
            let warmup = (0..<rebuildStreamCount).map { "\(category)w-\($0)" }
            var plan: [(stream: String, indices: [Int])] = []
            for n in 0..<rebuildStreamCount {
                let indices = Array(n * length ..< (n + 1) * length)
                plan.append((measured[n], indices))
                plan.append((warmup[n], indices))
            }
            (manifest.lastCommitPosition, manifest.lastPreparePosition) = try await append(plan, factory: factory, client: client)
            manifest.rebuildStreams = measured

        case .catchUp:
            var corpus = catchUpEvents
            if let reduced = catchUpCorpusOverride, reduced < catchUpEvents {
                corpus = reduced
                manifest.corpusReducedTo = reduced
            }
            guard corpus > 0 else { throw SeedError(description: "catch-up corpus must not be empty") }
            let streamCount = min(catchUpStreamCount, corpus)
            let plan = (0..<streamCount).map { n in
                ("\(category)-\(n)", Array(stride(from: n, to: corpus, by: streamCount)))
            }
            (manifest.lastCommitPosition, manifest.lastPreparePosition) = try await append(plan, factory: factory, client: client)
            manifest.catchUpCategory = category
            manifest.catchUpEvents = corpus
        }

        try await waitForByCategory(
            client: client, toReach: manifest.lastCommitPosition, prepare: manifest.lastPreparePosition, timeout: projectionTimeout
        )
        if let category = manifest.catchUpCategory {
            try await waitForCategory(client, category: category, count: manifest.catchUpEvents, timeout: projectionTimeout)
        }
        return manifest
    }

    /// Appends each stream's events in order (batched), `concurrency` streams at a time; returns the highest log
    /// position written. Each stream is new: its first batch expects no stream and every later batch the revision
    /// the previous one ended at, so a retried or duplicated batch fails loudly instead of changing seeded counts.
    private func append(_ plan: [(stream: String, indices: [Int])], factory: PayloadFactory, client: KurrentDBClient) async throws -> (commit: UInt64, prepare: UInt64) {
        let perAppend = max(1, min(appendBatchSize, 1_000_000 / max(1, factory.dataSize + factory.metadataSize)))
        return try await withThrowingTaskGroup(of: LogPosition.self) { group in
            var next = 0
            var highest = LogPosition.zero
            func addNext() {
                guard next < plan.count else { return }
                let (stream, indices) = plan[next]
                next += 1
                group.addTask {
                    var position = LogPosition.zero
                    for start in stride(from: 0, to: indices.count, by: perAppend) {
                        let events = indices[start ..< min(start + perAppend, indices.count)].map { k in
                            EventData(eventType: "BenchEvent", data: factory.data(index: k), contentType: .json, customMetadata: factory.metadata(index: k))
                        }
                        let expected: StreamRevision = start == 0 ? .noStream : .at(UInt64(start - 1))
                        let response = try await client.streams(specified: stream).append(events: events) {
                            $0.expectedRevision = expected
                        }
                        if let written = response.position {
                            position = max(position, LogPosition(commit: written.commit, prepare: written.prepare))
                        }
                    }
                    return position
                }
            }
            for _ in 0..<concurrency { addNext() }
            while let position = try await group.next() {
                highest = max(highest, position)
                addNext()
            }
            return (highest.commit, highest.prepare)
        }
    }
}

/// A position in the transaction log, ordered by commit, then prepare.
struct LogPosition: Comparable, Sendable {
    var commit: UInt64
    var prepare: UInt64

    static let zero = LogPosition(commit: 0, prepare: 0)

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.commit, lhs.prepare) < (rhs.commit, rhs.prepare)
    }

    /// Parses a projection position such as `C:1234/P:1234`; nil when either part is missing or negative (a fresh
    /// projection reports `C:0/P:-1`).
    init?(projectionPosition text: String) {
        func number(after tag: String) -> UInt64? {
            guard let range = text.range(of: tag) else { return nil }
            return UInt64(text[range.upperBound...].prefix(while: \.isNumber))
        }
        guard let commit = number(after: "C:"), let prepare = number(after: "P:") else { return nil }
        self.init(commit: commit, prepare: prepare)
    }

    init(commit: UInt64, prepare: UInt64) {
        self.commit = commit
        self.prepare = prepare
    }
}

// MARK: - $by_category

/// Enables `$by_category`, retrying while the projection subsystem is still starting (a request sent that early can
/// stay unanswered, so each attempt is bounded).
func enableByCategory(_ client: KurrentDBClient, timeout: Duration = .seconds(120)) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    while true {
        do {
            try await withTimeout(.seconds(5)) { try await client.projections(system: .byCategory).enable() }
            return
        } catch {
            if clock.now >= deadline { throw error }
            try await Task.sleep(for: .milliseconds(500))
        }
    }
}

/// Polls `$by_category`'s `detail().position` until it is at or past `(position, prepare)`, compared as a pair
/// (commit first). Verified on 26.2.3: every event has its own commit = prepare position (also within one multi-event
/// append), the append response carries the last event's position, and once the projection has processed that event
/// its position is exactly `C:<commit>/P:<prepare>` of it. A target of (0, 0) only needs the projection to answer.
func waitForByCategory(client: KurrentDBClient, toReach position: UInt64, prepare: UInt64 = 0, timeout: Duration) async throws {
    let target = LogPosition(commit: position, prepare: prepare)
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var last = "no answer"
    while true {
        do {
            let detail = try await withTimeout(.seconds(5)) { try await client.projections(system: .byCategory).detail() }
            if let detail {
                last = "\(detail.status) at \(detail.position)"
                if target == .zero { return }
                if let reached = LogPosition(projectionPosition: detail.position), reached >= target { return }
            }
        } catch {
            last = "\(error)"
        }
        guard clock.now < deadline else {
            throw Seeder.SeedError(description: "$by_category did not reach C:\(position)/P:\(prepare) within \(timeout) (last: \(last))")
        }
        try await Task.sleep(for: .milliseconds(500))
    }
}

/// Waits until `$ce-<category>` holds exactly `count` link events; throws if it holds more or does not get there.
private func waitForCategory(_ client: KurrentDBClient, category: String, count: Int, timeout: Duration) async throws {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)
    var held: UInt64 = 0
    while true {
        let last = try? await withTimeout(.seconds(5)) {
            try await client.streams(specified: "$ce-\(category)").read {
                $0.direction = .backward
                $0.revision = .end
                $0.limit = 1
            }.lazy.first(where: { _ in true }).map { try $0.event.record.revision }
        }
        held = last.map { $0 + 1 } ?? held
        if held == UInt64(count) { return }
        if held > UInt64(count) {
            throw Seeder.SeedError(description: "$ce-\(category) holds \(held) events, more than the \(count) seeded")
        }
        guard clock.now < deadline else {
            throw Seeder.SeedError(description: "$ce-\(category) holds \(held) of \(count) events after \(timeout)")
        }
        try await Task.sleep(for: .milliseconds(200))
    }
}
