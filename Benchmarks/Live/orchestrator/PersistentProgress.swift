import Foundation
import KurrentDB

/// The persistent-subscription groups of a trial and the server's acknowledged progress on them.
///
/// Which field is acknowledged progress was decided by `PersistentProgressLiveTests.checkpointAdvancesOnlyOnAck`
/// (kurrentdb 26.2.3): with 100 events delivered and none acked, `totalItems` is already 100 and
/// `lastCheckpointedEventPosition` is empty; after acking all 100 (and `checkPointAfterMilliseconds` + 2 s) it is `99`,
/// the revision of the last acked event in the `$ce-` stream, and it stays there after the consumer disconnects.
/// `totalItems` counts deliveries, not acks. So acknowledged progress = `lastCheckpointedEventPosition + 1` (0 when
/// empty), valid because each trial's group starts at the beginning of a `$ce-` stream that holds only the trial's
/// events (revision r is the (r+1)-th event).
///
/// Caveats: the checkpoint is the contiguous acked prefix (an event whose ack is lost holds it back until it is
/// retried and acked), and it is written at most every `checkpointAfter` (2 s default) once at least the minimum
/// count (1 here) of events was acked, so it lags acks by up to that interval. `read` therefore polls after the driver
/// exits until it reaches the events written or a bound passes.
enum PersistentProgress {
    /// Creates a group on `stream` (a `$ce-` stream) with the settings every client gets: links resolved, RoundRobin,
    /// checkpoint after 1 to 1000 acked events (default `checkpointAfter`), from the start of the stream.
    static func createGroup(client: KurrentDBClient, stream: String, group: String) async throws {
        try await client.persistentSubscriptions(stream: stream, group: group).create {
            $0.settings.resolveLink = true
            $0.settings.consumerStrategy = .roundRobin
            $0.settings.checkpointCount = 1 ... 1000
            $0.revision = .start
        }
    }

    /// Events of the group's stream acknowledged as observed by the server: `lastCheckpointedEventPosition + 1`, 0
    /// before the first checkpoint (empty field).
    static func acknowledgedEvents(_ info: PersistentSubscription.SubscriptionInfo) -> Int64 {
        acknowledgedEvents(checkpoint: info.lastCheckpointedEventPosition)
    }

    static func acknowledgedEvents(checkpoint: String) -> Int64 {
        Int64(checkpoint.trimmingCharacters(in: .whitespaces)).map { max(0, $0 + 1) } ?? 0
    }

    /// Polls the group's info until acknowledged progress reaches `expected` or `timeout` passes, and returns the last
    /// value read (the shortfall, if any, is `expected - value`). Throws only when no info could be read at all.
    static func read(client: KurrentDBClient, stream: String, group: String, expected: Int64, timeout: Duration) async throws -> Int64 {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        var last: Int64?
        var lastError: Error?
        while true {
            do {
                let info = try await withTimeout(.seconds(5)) {
                    try await client.persistentSubscriptions(stream: stream, group: group).getInfo()
                }
                let progress = acknowledgedEvents(info)
                last = progress
                if progress >= expected { return progress }
            } catch {
                lastError = error
            }
            guard clock.now < deadline else { break }
            try await Task.sleep(for: .milliseconds(500))
        }
        if let last { return last }
        throw lastError ?? TimeoutError(limit: timeout)
    }

    /// Bound for `read`: the checkpoint interval (2 s default) twice over, plus slack for a loaded server.
    static let readTimeout: Duration = .seconds(10)
}
