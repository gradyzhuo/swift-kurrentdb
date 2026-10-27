import Foundation
import LiveBenchCore

/// The comparison layer over one cell: per-step figures for every client, paired Swift-vs-.NET ratios with their
/// verdicts, and the cell's sustained ceiling. Everything here is computed from a single `CellResult`, so no number is
/// ever divided by a number from another cell (another job, another VM).
///
/// Rules (spec "Measurement rules" and "Comparison layer"):
/// - A trial counts only when it has a result and no error. A round pairs Swift and .NET at a rate only when both
///   have such a trial in that round; a round where one side is missing contributes nothing.
/// - Ratios are oriented so that higher means Swift is worse (Swift ÷ .NET when lower is better, .NET ÷ Swift when
///   higher is better) and estimated with `estimateRatio` (95% Student t over round log-ratios).
/// - A step gets ratios (and verdicts) only when both clients sustained it in every valid trial and every paired trial
///   had server headroom. A failing gate is "system-limited", a missing sample "headroom unavailable": the step is
///   shown (per-client figures) but no SDK comparison is drawn from it. The same holds for the ceiling ratio.
/// - A censored percentile (rank among non-successes) on either side drops that round from that percentile's ratio.
/// - "Backlog not growing" uses the drivers' backlog samples (`TrialResult.backlog`, `backlogGrew`): a client that
///   falls slowly behind can finish everything within the deadline and the drain, so the loss criterion alone would
///   miss it. A result without samples (ghz) counts as not grown: unknown is not growth.
struct CellAnalysis {
    static let swift = "swift"
    static let dotnet = "dotnet"
    static let ghz = "ghz"

    let result: CellResult
    let minimumRounds: Int
    let steps: [StepAnalysis]
    /// Highest rate each client sustained per round, paired (.NET ÷ Swift). nil when the cell is aborted, has one
    /// rate or lacks one of the two clients.
    let ceiling: MetricRatio?
    /// Why `ceiling` has no ratio or no verdict, when it hasn't.
    let ceilingNote: String?

    init(_ result: CellResult) {
        self.result = result
        let cell = result.cell
        minimumRounds = cell.tier == .headline ? 5 : 3
        let figures = result.trials.map { TrialFigures($0, cell: cell) }
        let hasBoth = figures.contains { $0.trial.driver == Self.swift } && figures.contains { $0.trial.driver == Self.dotnet }
        let aborted = result.abortedReason != nil

        let rates = (cell.rates + result.trials.map(\.rate)).reduce(into: [Double]()) { if !$0.contains($1) { $0.append($1) } }
        steps = rates.map { rate in
            StepAnalysis(
                rate: rate, figures: figures.filter { $0.trial.rate == rate }, kind: cell.kind,
                compare: hasBoth, aborted: aborted, minimumRounds: result.cell.tier == .headline ? 5 : 3
            )
        }

        guard hasBoth, !aborted, rates.count > 1 else {
            ceiling = nil
            ceilingNote = nil
            return
        }
        let (ceiling, note) = Self.ceiling(figures: figures, rates: rates, minimumRounds: minimumRounds)
        self.ceiling = ceiling
        ceilingNote = note
    }

    /// Per round, the highest rate each client sustained (0 when none), from rounds where both ran every rate validly.
    private static func ceiling(figures: [TrialFigures], rates: [Double], minimumRounds: Int) -> (MetricRatio?, String?) {
        let rounds = Set(figures.map(\.trial.round)).sorted()
        var pairs: [RoundPair] = []
        var paired: [TrialFigures] = []
        var bothAtTop = 0
        for round in rounds {
            func highest(_ driver: String) -> (Double, [TrialFigures])? {
                let valid = figures.filter { $0.trial.round == round && $0.trial.driver == driver && $0.valid }
                guard Set(valid.map(\.trial.rate)).count == rates.count else { return nil }
                return (valid.filter(\.sustained).map(\.trial.rate).max() ?? 0, valid)
            }
            guard let s = highest(Self.swift), let d = highest(Self.dotnet) else { continue }
            pairs.append(RoundPair(swift: s.0, dotnet: d.0))
            paired += s.1 + d.1
            if s.0 == rates.max(), d.0 == rates.max() { bothAtTop += 1 }
        }
        guard !pairs.isEmpty else { return (nil, "No round has a valid trial of both clients at every rate, so there is no paired ceiling.") }
        if bothAtTop == pairs.count {
            return (nil, "Both clients sustained every step in every paired round: their ceilings lie above the tested range, so there is no ceiling ratio.")
        }
        let (estimate, verdict) = estimateRatio(pairs, direction: .higherIsBetter, minimumRounds: minimumRounds)
        guard estimate != nil else {
            return (nil, "Fewer than two paired rounds in which both clients sustained at least one step, so there is no ceiling ratio.")
        }
        let headroom = HeadroomState(paired)
        guard headroom == .ok else { return (nil, "no ceiling ratio: \(headroom.noComparisonReason)") }
        let ratio = MetricRatio(metric: .ceiling, estimate: estimate, verdict: verdict)
        let zero = pairs.contains { $0.swift == 0 || $0.dotnet == 0 }
        let note = [
            "A client that sustained the highest step has a ceiling of at least that rate, so the ratio understates the gap when one side sustained everything.",
            zero ? "Rounds where a client sustained no step at all have no ratio and are left out." : nil,
        ].compactMap { $0 }.joined(separator: " ")
        return (ratio, note)
    }
}

/// One rate step of a cell.
struct StepAnalysis {
    let rate: Double
    /// Every in-process client at this rate (Swift first, then .NET, then any other driver), ghz excluded.
    let clients: [ClientStep]
    /// ghz, the transport reference: shown, never compared.
    let ghz: ClientStep?
    /// nil when the cell does not have both Swift and .NET.
    let comparison: StepComparison?

    init(rate: Double, figures: [TrialFigures], kind: ScenarioKind, compare: Bool, aborted: Bool, minimumRounds: Int) {
        self.rate = rate
        let drivers = figures.map(\.trial.driver).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let order = [CellAnalysis.swift, CellAnalysis.dotnet]
        let sorted = drivers.filter { $0 != CellAnalysis.ghz }
            .sorted { (order.firstIndex(of: $0) ?? 2, $0) < (order.firstIndex(of: $1) ?? 2, $1) }
        clients = sorted.map { driver in ClientStep(driver: driver, figures: figures.filter { $0.trial.driver == driver }) }
        ghz = drivers.contains(CellAnalysis.ghz) ? ClientStep(driver: CellAnalysis.ghz, figures: figures.filter { $0.trial.driver == CellAnalysis.ghz }) : nil
        guard compare else {
            comparison = nil
            return
        }
        comparison = StepComparison(
            figures: figures, kind: kind, swift: clients.first { $0.driver == CellAnalysis.swift },
            dotnet: clients.first { $0.driver == CellAnalysis.dotnet }, aborted: aborted, minimumRounds: minimumRounds
        )
    }
}

/// Server headroom over a set of trials: any failing gate wins over any missing sample.
enum HeadroomState: Equatable {
    case ok, systemLimited, unavailable

    init(_ figures: [TrialFigures]) {
        if figures.contains(where: { $0.trial.headroom.map { !hasHeadroom($0) } ?? false }) {
            self = .systemLimited
        } else if figures.contains(where: { $0.trial.headroom == nil }) {
            self = .unavailable
        } else {
            self = .ok
        }
    }

    var label: String {
        switch self {
        case .ok: "headroom ok"
        case .systemLimited: "system-limited"
        case .unavailable: "headroom unavailable"
        }
    }

    /// Why a step (or the ceiling) has no comparison.
    var noComparisonReason: String {
        switch self {
        case .ok: ""
        case .systemLimited: "system-limited: server headroom gate failed; no SDK comparison"
        case .unavailable: "headroom unavailable: server headroom not measured; no SDK comparison"
        }
    }
}

/// The Swift-vs-.NET comparison at one step.
struct StepComparison {
    var headroom: HeadroomState
    var ratios: [MetricRatio]
    /// Why the step has no ratios at all (aborted cell, not sustained, nothing paired).
    var noRatioReason: String?
    var pairedRounds: Int

    init(figures: [TrialFigures], kind: ScenarioKind, swift: ClientStep?, dotnet: ClientStep?, aborted: Bool, minimumRounds: Int) {
        var pairs: [(swift: TrialFigures, dotnet: TrialFigures)] = []
        for round in Set(figures.map(\.trial.round)).sorted() {
            let valid = figures.filter { $0.trial.round == round && $0.valid }
            if let s = valid.first(where: { $0.trial.driver == CellAnalysis.swift }), let d = valid.first(where: { $0.trial.driver == CellAnalysis.dotnet }) {
                pairs.append((s, d))
            }
        }
        pairedRounds = pairs.count
        headroom = HeadroomState(pairs.flatMap { [$0.swift, $0.dotnet] })
        ratios = []
        if aborted {
            noRatioReason = "cell aborted: no ratios"
            return
        }
        guard !pairs.isEmpty else {
            noRatioReason = "no round in which both clients produced a valid trial"
            return
        }
        // A saturated server explains everything else at the step, so it is named first.
        if headroom == .systemLimited {
            noRatioReason = HeadroomState.systemLimited.noComparisonReason
            return
        }
        let unsustained = [(swift, "Swift"), (dotnet, ".NET")].filter { !($0.0?.sustained ?? false) }.map(\.1)
        guard unsustained.isEmpty else {
            noRatioReason = "not sustained by \(unsustained.joined(separator: " and ")): no ratio"
            return
        }
        if headroom == .unavailable {
            noRatioReason = HeadroomState.unavailable.noComparisonReason
            return
        }
        noRatioReason = nil
        ratios = RatioMetric.stepMetrics(kind).map { metric in
            let roundPairs = pairs.map { RoundPair(swift: metric.value($0.swift), dotnet: metric.value($0.dotnet)) }
            let (estimate, verdict) = estimateRatio(roundPairs, direction: metric.direction, minimumRounds: minimumRounds)
            return MetricRatio(metric: metric, estimate: estimate, verdict: metric.hasVerdict ? verdict : nil)
        }
    }
}

/// A compared metric, with its orientation.
enum RatioMetric: String, CaseIterable {
    case p50, p99, cpuPerThousand, maxRss, ackedProgressRate, catchUpTime, ceiling

    static func stepMetrics(_ kind: ScenarioKind) -> [RatioMetric] {
        switch kind {
        case .persistentSubscription: [.p50, .p99, .ackedProgressRate, .cpuPerThousand, .maxRss]
        case .catchUp: [.p50, .p99, .catchUpTime, .cpuPerThousand, .maxRss]
        default: [.p50, .p99, .cpuPerThousand, .maxRss]
        }
    }

    /// Catch-up time is shown with its ratio but no verdict: phase 1 (reading the corpus) runs before the monitored
    /// window and saturates the server by design, so the headroom gate cannot vouch for it.
    var hasVerdict: Bool { self != .catchUpTime }

    var direction: Direction {
        switch self {
        case .ackedProgressRate, .ceiling: .higherIsBetter
        default: .lowerIsBetter
        }
    }

    var title: String {
        switch self {
        case .p50: "p50 latency"
        case .p99: "p99 latency"
        case .cpuPerThousand: "Client CPU per 1,000 successful operations"
        case .maxRss: "Peak RSS"
        case .ackedProgressRate: "Acknowledged progress rate (server, at the window end)"
        case .catchUpTime: "Catch-up time over the corpus"
        case .ceiling: "Highest sustained rate"
        }
    }

    /// "Swift ÷ .NET, lower is better" or ".NET ÷ Swift, higher is better".
    var orientation: String {
        direction == .lowerIsBetter ? "Swift ÷ .NET, lower is better" : ".NET ÷ Swift, higher is better"
    }

    func value(_ f: TrialFigures) -> Double? {
        switch self {
        case .p50: f.p50.micros
        case .p99: f.p99.micros
        case .cpuPerThousand: f.cpuPerThousandSeconds
        case .maxRss: f.maxRssBytes
        case .ackedProgressRate: f.ackedProgressRate
        case .catchUpTime: f.catchUpSeconds
        case .ceiling: nil
        }
    }
}

/// A ratio exists only where a comparison is allowed (both sustained, server headroom). Its verdict is nil only for a
/// metric without one (`RatioMetric.hasVerdict`).
struct MetricRatio {
    var metric: RatioMetric
    var estimate: RatioEstimate?
    var verdict: Verdict?
}

/// One client at one step, over its rounds.
struct ClientStep {
    let driver: String
    let figures: [TrialFigures]
    var valid: [TrialFigures] { figures.filter(\.valid) }
    /// Sustained in every valid trial (and at least one).
    var sustained: Bool { !valid.isEmpty && valid.allSatisfy(\.sustained) }
    var sustainedCount: Int { valid.filter(\.sustained).count }
    var headroom: HeadroomState { HeadroomState(valid) }

    /// Lower median over the valid trials, censored values ranking above every number.
    func medianPercentile(_ key: KeyPath<TrialFigures, PercentileValue>) -> PercentileValue? {
        let values = valid.map { $0[keyPath: key] }.sorted { a, b in
            switch (a, b) {
            case let (.micros(x), .micros(y)): x < y
            case (.micros, .censored): true
            default: false
            }
        }
        return values.isEmpty ? nil : values[(values.count - 1) / 2]
    }

    /// Lower median of the finite values over the valid trials.
    func median(_ value: (TrialFigures) -> Double?) -> Double? {
        let values = valid.compactMap(value).filter(\.isFinite).sorted()
        return values.isEmpty ? nil : values[(values.count - 1) / 2]
    }

    func total(_ value: (TrialResult) -> Int) -> Int { valid.compactMap(\.trial.result).map(value).reduce(0, +) }
}

/// Figures of one trial, computed once.
struct TrialFigures {
    let trial: TrialRecord
    let valid: Bool
    let sustained: Bool
    let p50: PercentileValue
    let p99: PercentileValue
    let p999: PercentileValue
    /// Successful operations per second of the measure window.
    let achievedRate: Double?
    let cpuPerThousandSeconds: Double?
    let maxRssBytes: Double?
    /// Server-observed acknowledged events per second of the measure window (persistent subscription): the checkpoint
    /// read at the window's end ÷ the measured seconds.
    let ackedProgressRate: Double?
    let catchUpSeconds: Double?

    init(_ trial: TrialRecord, cell: Cell) {
        self.trial = trial
        guard trial.error == nil, let result = trial.result else {
            valid = false
            sustained = false
            p50 = .censored
            p99 = .censored
            p999 = .censored
            achievedRate = nil
            cpuPerThousandSeconds = nil
            maxRssBytes = nil
            ackedProgressRate = nil
            catchUpSeconds = nil
            return
        }
        valid = true
        let lost = result.failed + result.dropped + result.timedOut
        sustained = isSustained(
            scheduled: result.scheduled, succeeded: result.succeeded, lost: lost,
            targetRate: trial.rate, measuredSeconds: result.measuredSeconds, backlogGrew: result.backlog?.grew ?? false
        )
        let histogram = (trial.histogram ?? HistogramFile(buckets: [])).histogram()
        p50 = percentile(50, successes: histogram, scheduled: result.scheduled)
        p99 = percentile(99, successes: histogram, scheduled: result.scheduled)
        p999 = percentile(99.9, successes: histogram, scheduled: result.scheduled)
        let seconds = result.measuredSeconds.isFinite && result.measuredSeconds > 0 ? result.measuredSeconds : nil
        achievedRate = seconds.map { Double(result.succeeded) / $0 }
        // ghz measures neither CPU nor RSS (zeros); an all-failed trial has no per-operation cost.
        let cpu = result.cpuUserSeconds + result.cpuSystemSeconds
        cpuPerThousandSeconds = result.timing == .scheduled && result.succeeded > 0 && cpu.isFinite && cpu > 0
            ? cpu / Double(result.succeeded) * 1000 : nil
        maxRssBytes = result.timing == .scheduled && result.maxRssBytes > 0 ? Double(result.maxRssBytes) : nil
        ackedProgressRate = cell.kind == .persistentSubscription
            ? zip(trial.serverAckedAtWindowEnd, seconds).map { Double($0) / $1 } : nil
        catchUpSeconds = result.catchUpSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
    }
}

extension PercentileValue {
    var micros: Double? {
        if case let .micros(value) = self { Double(value) } else { nil }
    }
}

private func zip<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
