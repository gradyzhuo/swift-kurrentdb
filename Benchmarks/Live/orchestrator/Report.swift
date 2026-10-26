import Foundation
import LiveBenchCore

/// The comparison report: one self-contained HTML page (inline CSS and SVG, no scripts, no external resources) with
/// light and dark themes. Every figure of a cell comes from that cell's `CellAnalysis`; nothing is compared across
/// cells. All text from results (errors, notes, metadata) is redacted (`HostRedaction`) and HTML-escaped.
enum Report {
    static func render(_ cells: [CellResult]) -> String {
        let analyses = cells.map { cell in
            // Fails closed: a cell that cannot be redacted is shown only as an aborted placeholder.
            CellAnalysis((try? HostRedaction.scrubbing(cell)) ?? CellResult(
                cell: cell.cell, trials: [], metadata: RunMetadata(),
                abortedReason: "its results could not be redacted for publication and are not shown"
            ))
        }
        var html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Live client benchmarks</title>
        <style>\(css)</style>
        </head>
        <body>
        <main>
        <h1>Swift vs .NET KurrentDB clients on a live server</h1>
        <p class="lede">Open-loop load against one KurrentDB server per cell. Each cell (scenario × event size) ran in its own
        job on one VM, with the clients interleaved over rounds in rotated order. Ratios pair the two clients round by
        round inside a cell; numbers from different cells are never divided.</p>

        """
        html += readingGuide
        html += index(analyses)
        for analysis in analyses { html += section(analysis) }
        html += "</main>\n</body>\n</html>\n"
        return html
    }

    // MARK: - Page sections

    private static var readingGuide: String {
        let t = EvaluationThresholds.self
        return """
        <section class="guide">
        <h2>How to read this report</h2>
        <ul>
        <li><strong>Ratios</strong> are oriented so that <em>higher means Swift is worse</em>: Swift ÷ .NET for
        lower-is-better metrics (latency, CPU per operation, RSS, catch-up time), .NET ÷ Swift for higher-is-better
        metrics (acknowledged progress, highest sustained rate). The interval is a 95% Student t interval over the
        round-level log-ratios. Verdict against \(fixed(targetRatio, 1))×: <em>meets</em> when the upper bound is below it,
        <em>misses</em> when the lower bound is above it, otherwise <em>inconclusive</em>; fewer paired rounds than the
        tier's minimum (5 headline, 3 appendix) gives <em>insufficient rounds</em>.</li>
        <li><strong>Pairing.</strong> A round contributes to a ratio only when both clients have a valid trial (no error)
        at that rate in that round. A percentile that is censored on either side drops that round from that percentile's
        ratio.</li>
        <li><strong>Percentiles</strong> are ranked over every scheduled operation; failures, drops and timeouts rank as
        +∞, and a percentile that lands among them reads <em>&gt; deadline</em>. Tables show the lower median over the
        valid rounds.</li>
        <li><strong>Sustained</strong>: successful rate ≥ \(fixed(t.sustainedRateFraction * 100, 0))% of the target and
        failed + dropped + timed out ≤ \(fixed(t.maxLossRatio * 100, 1))% of scheduled, in every valid round (a growing
        backlog shows up as drops and timeouts under the in-flight cap and deadline). A step gets ratios only when both
        clients sustained it.</li>
        <li><strong>Server headroom</strong>: every server core ≤ \(fixed(t.maxCoreBusy * 100, 0))% busy, disk await ≤
        \(fixed(t.maxDiskAwaitMillis, 0)) ms, disk queue ≤ \(fixed(t.maxDiskQueueDepth, 0)), and the
        <code>$by_category</code> backlog growing by at most \(fixed(t.maxBufferedGrowthFraction * 100, 0))% of the events
        written. A step where any paired trial fails the gate is <em>system-limited</em>; one without a measurement is
        <em>headroom unavailable</em>. Such a step is shown with each client's figures, but no ratio or verdict is
        drawn from it.</li>
        <li><strong>Setting.</strong> The network is loopback and the server is co-located with the client on one VM
        (server and client pinned to separate cores): real network effects are not included, and the two still share
        memory bandwidth, caches and disk.</li>
        <li><strong>Harness floor</strong> (each driver's scheduler with a no-op operation, release build, after warmup,
        p50 / p99; measured on a development Mac with Apple Silicon, not on the CI runner): Swift 1000/s 7 / 241–282 µs, 8000/s 3–6 / 31–88 µs; .NET 1000/s 5–7 / 111–153 µs,
        8000/s 5–6 / 73–138 µs. Latencies close to these floors say more about the harness than the client.</li>
        <li><strong>CPU</strong> is process CPU from the start of the measure window to the end of the drain. The .NET
        thread pool's workers spin before sleeping (runtime default), which costs CPU even with a no-op operation: about
        0.2 cores at 1000/s and 1.3 cores at 8000/s, against about 0.12 cores for Swift's harness at 8000/s (development Mac). Read the CPU
        ratios with that in mind.</li>
        <li><strong>ghz</strong> is a <em>transport reference</em> for append and rebuild cells: plain gRPC calls with
        latency timed from the RPC start (not from the schedule), no drops (a full worker pool waits), no JSON decoding.
        It is shown on its own and never put in a ratio.</li>
        </ul>
        </section>

        """
    }

    private static func index(_ analyses: [CellAnalysis]) -> String {
        guard !analyses.isEmpty else { return "<p>No cell results.</p>\n" }
        var html = "<nav class=\"cells\"><h2>Cells</h2><ul>\n"
        for a in analyses {
            let cell = a.result.cell
            let status: String
            if a.result.abortedReason != nil {
                status = "<span class=\"badge bad\">aborted</span>"
            } else {
                let failed = a.result.trials.filter { $0.error != nil }.count
                status = failed == 0 ? "" : "<span class=\"badge warn\">\(failed) failed trial\(failed == 1 ? "" : "s")</span>"
            }
            html += "<li><a href=\"#\(anchor(cell.id))\">\(esc(cell.id))</a> <span class=\"muted\">\(esc(cell.tier.rawValue))</span> \(status)</li>\n"
        }
        return html + "</ul></nav>\n"
    }

    private static func section(_ a: CellAnalysis) -> String {
        let cell = a.result.cell
        let metadata = a.result.metadata
        var html = "<section class=\"cell\" id=\"\(anchor(cell.id))\">\n<h2>\(esc(cell.id))</h2>\n"
        var facts = [
            kindTitle(cell.kind), "\(grouped(cell.eventSize)) B events", cell.tls ? "TLS" : "no TLS",
            "\(cell.tier.rawValue) tier", "minimum \(a.minimumRounds) paired rounds",
        ]
        if let length = cell.streamLength { facts.insert("streams of \(grouped(length)) events", at: 1) }
        if let consumers = cell.consumers, consumers > 1 { facts.append("\(consumers) consumers") }
        if let scenario = metadata.scenario {
            facts.append("\(scenario.rounds) round\(scenario.rounds == 1 ? "" : "s"), \(fixed(scenario.measureSeconds, 0)) s measure, deadline \(grouped(scenario.deadlineMillis)) ms, in-flight cap \(scenario.inFlightCap)")
            if scenario.smoke { facts.append("smoke run (not a published result)") }
        }
        html += "<p class=\"facts\">\(facts.map(esc).joined(separator: " · "))</p>\n"
        if let reason = a.result.abortedReason {
            html += "<p class=\"alert\"><strong>Aborted:</strong> \(esc(reason)). The trials before it are shown; no ratios are computed for this cell.</p>\n"
        }
        if let reduced = metadata.corpusReducedTo {
            html += "<p class=\"note\"><strong>Reduced corpus:</strong> the catch-up corpus was reduced to \(grouped(reduced)) events to fit the runner's disk budget (instead of 1,000,000); catch-up times are for that corpus.</p>\n"
        }
        html += chart(a)
        html += stepTable(a)
        html += comparisonTable(a)
        html += ghzTable(a)
        html += problems(a)
        html += metadataBlock(metadata)
        return html + "</section>\n"
    }

    // MARK: - Step table

    private static func stepTable(_ a: CellAnalysis) -> String {
        let kind = a.result.cell.kind
        let subscription = kind == .persistentSubscription || kind == .catchUp
        var head = ["Rate", "Client", "Valid rounds", "Achieved", "p50", "p99", "p99.9", "Failed / dropped / timed out", "CPU per 1,000 ops", "Peak RSS"]
        if subscription { head += ["Written / delivered", "Acked (server)"] }
        if kind == .catchUp { head.append("Catch-up time") }
        head += ["Sustained", "Headroom"]
        var html = "<h3>Rate steps</h3>\n<p class=\"caption\">Target rate in \(esc(rateUnit(kind))); per client the lower median over valid rounds, loss counts summed over them. “≥” marks the upper percentiles (p99, p99.9) of a step the client did not sustain: censored, the true value may be higher.\(subscription ? " Written / delivered / acked are medians per round; a shortfall is reported, not a failure." : "")</p>\n"
        html += "<div class=\"scroll\"><table class=\"steps\">\n<thead><tr>\(head.map { "<th>\(esc($0))</th>" }.joined())</tr></thead>\n<tbody>\n"
        for step in a.steps {
            for (index, client) in step.clients.enumerated() {
                var cells: [String] = []
                cells.append(index == 0 ? "<th scope=\"row\" rowspan=\"\(step.clients.count)\">\(esc(rateText(step.rate)))</th>" : "")
                cells.append("<td>\(esc(clientName(client.driver)))</td>")
                cells.append("<td class=\"num\">\(client.valid.count) of \(client.figures.count)</td>")
                cells.append("<td class=\"num\">\(client.median { $0.achievedRate }.map { esc(rateText($0)) } ?? "—")</td>")
                cells.append("<td class=\"num\">\(latency(client.medianPercentile(\.p50)))</td>")
                // Upper percentiles of a step the client did not sustain are censored (lower bounds).
                let unsustained = !client.valid.isEmpty && !client.sustained
                cells.append("<td class=\"num\">\(latency(client.medianPercentile(\.p99), lowerBound: unsustained))</td>")
                cells.append("<td class=\"num\">\(latency(client.medianPercentile(\.p999), lowerBound: unsustained))</td>")
                let losses = client.valid.isEmpty ? "—" : "\(grouped(client.total(\.failed))) / \(grouped(client.total(\.dropped))) / \(grouped(client.total(\.timedOut)))"
                cells.append("<td class=\"num\">\(losses)</td>")
                cells.append("<td class=\"num\">\(client.median { $0.cpuPerThousandSeconds }.map { esc(duration(seconds: $0)) } ?? "—")</td>")
                cells.append("<td class=\"num\">\(client.median { $0.maxRssBytes }.map { esc(megabytes($0)) } ?? "—")</td>")
                if subscription {
                    let written = client.median { $0.trial.result.map { Double($0.validation.expectedEvents) } }
                    let delivered = client.median { $0.trial.result.map { Double($0.validation.receivedEvents) } }
                    let acked = client.median { $0.trial.serverAckedProgress.map(Double.init) }
                    cells.append("<td class=\"num\">\(count(written)) / \(count(delivered))</td>")
                    cells.append("<td class=\"num\">\(kind == .persistentSubscription ? count(acked) : "n/a")</td>")
                }
                if kind == .catchUp {
                    cells.append("<td class=\"num\">\(client.median { $0.catchUpSeconds }.map { esc(duration(seconds: $0)) } ?? "—")</td>")
                }
                let sustained = client.valid.isEmpty
                    ? "<span class=\"badge bad\">no valid trial</span>"
                    : client.sustained
                        ? "<span class=\"badge good\">sustained</span>"
                        : "<span class=\"badge bad\">not sustained</span> <span class=\"muted\">(\(client.sustainedCount) of \(client.valid.count))</span>"
                cells.append("<td>\(sustained)</td>")
                cells.append("<td>\(headroomBadge(client.headroom, empty: client.valid.isEmpty))</td>")
                html += "<tr>\(cells.joined())</tr>\n"
            }
        }
        return html + "</tbody></table></div>\n"
    }

    // MARK: - Comparison

    private static func comparisonTable(_ a: CellAnalysis) -> String {
        let comparisons = a.steps.compactMap { step in step.comparison.map { (step.rate, $0) } }
        guard !comparisons.isEmpty else { return "" }
        if a.result.abortedReason != nil {
            return "<h3>Swift vs .NET</h3>\n<p>No ratios: the cell was aborted.</p>\n"
        }
        var html = "<h3>Swift vs .NET</h3>\n<p class=\"caption\">Higher means Swift is worse. A step is compared only when both clients sustained it and the server had headroom in every paired trial.</p>\n"
        html += "<div class=\"scroll\"><table class=\"ratios\">\n<thead><tr><th>Step</th><th>Metric</th><th>Ratio</th><th>95% CI</th><th>Rounds</th><th>Verdict</th></tr></thead>\n<tbody>\n"
        for (rate, comparison) in comparisons {
            let label = TrialRunner.rateLabel(rate)
            if let reason = comparison.noRatioReason {
                html += "<tr data-rate=\"\(esc(label))\"><th scope=\"row\">\(esc(rateText(rate)))</th><td colspan=\"5\" class=\"muted\">\(esc(reason))</td></tr>\n"
                continue
            }
            for ratio in comparison.ratios {
                html += ratioRow(ratio, rateCell: rateText(rate), dataRate: label, minimum: a.minimumRounds)
            }
        }
        if let ceiling = a.ceiling, ceiling.estimate != nil {
            html += ratioRow(ceiling, rateCell: "all steps", dataRate: "ceiling", minimum: a.minimumRounds)
        }
        html += "</tbody></table></div>\n"
        if let note = a.ceilingNote { html += "<p class=\"caption\">Highest sustained rate: \(esc(note))</p>\n" }
        html += fairnessNotes(a.result.cell.kind)
        return html
    }

    private static func ratioRow(_ ratio: MetricRatio, rateCell: String, dataRate: String, minimum: Int) -> String {
        let metric = "\(esc(ratio.metric.title))<br><span class=\"muted\">\(esc(ratio.metric.orientation))</span>"
        let point = ratio.estimate.map { "\(fixed($0.point, 2))×" } ?? "—"
        let interval = ratio.estimate.map { "\(fixed($0.lower, 2)) – \(fixed($0.upper, 2))" } ?? "—"
        let rounds = ratio.estimate.map { "\($0.rounds)" } ?? "&lt; 2"
        let verdict: String
        switch ratio.verdict {
        case .meets: verdict = "<span class=\"badge good\">meets</span>"
        case .misses: verdict = "<span class=\"badge bad\">misses</span>"
        case .inconclusive: verdict = "<span class=\"badge warn\">inconclusive</span>"
        case .insufficientRounds: verdict = "<span class=\"badge muted\">insufficient rounds</span> <span class=\"muted\">(minimum \(minimum))</span>"
        }
        return "<tr data-rate=\"\(esc(dataRate))\"><th scope=\"row\">\(esc(rateCell))</th><td>\(metric)</td><td class=\"num\">\(point)</td><td class=\"num\">\(interval)</td><td class=\"num\">\(rounds)</td><td>\(verdict)</td></tr>\n"
    }

    private static func fairnessNotes(_ kind: ScenarioKind) -> String {
        var notes = [
            "CPU per 1,000 operations includes the .NET thread pool's default spin (with a no-op operation on a development Mac: about 0.2 cores at 1000/s, 1.3 cores at 8000/s; Swift's harness about 0.12 cores at 8000/s).",
            "Peak RSS is the process lifetime peak (warmup included).",
        ]
        if kind == .persistentSubscription {
            notes.insert(contentsOf: [
                "Persistent subscription consumers run with each client's default buffer: .NET bufferSize 10, Swift 1000. The buffer bounds the unacknowledged events the server sends one consumer.",
                "The .NET client needs a separate persistent subscriptions client, so a .NET trial has a second gRPC channel; the Swift driver uses one client.",
                "Acknowledged progress is the server's checkpoint of the measured group after the driver exits; it lags acks by up to the checkpoint interval.",
            ], at: 0)
        }
        if kind == .persistentSubscription || kind == .catchUp {
            notes.append("Each client's writer runs in the same process as its subscriber, so CPU and RSS cover writing and consuming.")
        }
        return "<ul class=\"fairness\">\(notes.map { "<li>\(esc($0))</li>" }.joined())</ul>\n"
    }

    // MARK: - ghz, problems, metadata

    private static func ghzTable(_ a: CellAnalysis) -> String {
        let steps = a.steps.compactMap { step in step.ghz.map { (step.rate, $0) } }
        guard !steps.isEmpty else { return "" }
        var html = "<h3>Transport reference: ghz</h3>\n<p class=\"caption\">Plain gRPC calls, latency from the RPC start (not from the schedule), no drops, no decoding, CPU and RSS not measured. Shown for orientation only; never in a ratio.</p>\n"
        html += "<div class=\"scroll\"><table class=\"ghz\">\n<thead><tr><th>Rate</th><th>Valid runs</th><th>Achieved</th><th>p50</th><th>p99</th><th>p99.9</th><th>Failed / timed out</th></tr></thead>\n<tbody>\n"
        for (rate, ghz) in steps {
            let losses = ghz.valid.isEmpty ? "—" : "\(grouped(ghz.total(\.failed))) / \(grouped(ghz.total(\.timedOut)))"
            html += "<tr><th scope=\"row\">\(esc(rateText(rate)))</th><td class=\"num\">\(ghz.valid.count) of \(ghz.figures.count)</td><td class=\"num\">\(ghz.median { $0.achievedRate }.map { esc(rateText($0)) } ?? "—")</td><td class=\"num\">\(latency(ghz.medianPercentile(\.p50)))</td><td class=\"num\">\(latency(ghz.medianPercentile(\.p99)))</td><td class=\"num\">\(latency(ghz.medianPercentile(\.p999)))</td><td class=\"num\">\(losses)</td></tr>\n"
        }
        return html + "</tbody></table></div>\n"
    }

    private static func problems(_ a: CellAnalysis) -> String {
        let trials = a.result.trials.filter { $0.error != nil || !($0.notes ?? []).isEmpty }
        guard !trials.isEmpty else { return "" }
        var html = "<details class=\"problems\"><summary>Failed trials and notes (\(trials.count))</summary>\n<ul>\n"
        for trial in trials.sorted(by: { ($0.round, $0.rate, $0.driver) < ($1.round, $1.rate, $1.driver) }) {
            let where_ = "round \(trial.round), \(rateText(trial.rate)), \(clientName(trial.driver))"
            if let error = trial.error {
                html += "<li><strong>\(esc(where_)) failed:</strong> <code>\(esc(error))</code></li>\n"
            }
            for note in trial.notes ?? [] {
                html += "<li>\(esc(where_)): \(esc(note))</li>\n"
            }
        }
        return html + "</ul></details>\n"
    }

    private static func metadataBlock(_ m: RunMetadata) -> String {
        var rows: [(String, String?)] = [
            ("Run date (UTC)", m.runDate),
            ("SDK commit", m.sdkCommit),
            ("Harness commit", m.harnessCommit),
            ("Swift toolchain", m.swiftToolchain),
            (".NET runtime", m.dotnetRuntime),
            ("KurrentDB.Client", m.kurrentDBClientVersion),
            ("ghz", m.ghzVersion),
            ("Build flags", m.buildFlags),
            ("Server image", m.serverImage),
            ("Server image digest", m.serverImageDigest),
            ("Runner image", m.runnerImageVersion),
            ("CPU model", m.cpuModel),
        ]
        if let s = m.scenario {
            rows.append(("Scenario", "rates \(s.rates.map(rateText).joined(separator: ", ")); \(s.rounds) rounds; warmup \(fixed(s.warmupSeconds, 0)) s, measure \(fixed(s.measureSeconds, 0)) s, drain \(fixed(s.drainSeconds, 0)) s; in-flight cap \(s.inFlightCap); deadline \(s.deadlineMillis) ms; seed \(s.seed)\(s.smoke ? "; smoke" : "")"))
        }
        for client in m.clients ?? [] {
            rows.append(("Client \(client.client)", "\(client.clientVersion) on \(client.runtime)"))
        }
        for (key, value) in (m.serverConfiguration ?? [:]).sorted(by: { $0.key < $1.key }) {
            rows.append(("Server: \(key)", value))
        }
        let items = rows.compactMap { key, value in value.map { "<dt>\(esc(key))</dt><dd>\(esc($0))</dd>" } }
        return "<details class=\"metadata\"><summary>Reproducibility metadata</summary>\n<dl>\(items.joined(separator: "\n"))</dl></details>\n"
    }

    // MARK: - Chart

    /// p50 and p99 per step (median over valid rounds) for Swift and .NET on a log scale; a censored point is a
    /// triangle on the top edge. ghz is not drawn.
    private static func chart(_ a: CellAnalysis) -> String {
        struct Series { var driver: String; var name: String; var key: KeyPath<TrialFigures, PercentileValue>; var dashed: Bool }
        let series = [CellAnalysis.swift, CellAnalysis.dotnet].flatMap { driver in
            [Series(driver: driver, name: "p50", key: \.p50, dashed: false), Series(driver: driver, name: "p99", key: \.p99, dashed: true)]
        }
        let steps = a.steps
        func value(_ step: StepAnalysis, _ s: Series) -> PercentileValue? {
            step.clients.first { $0.driver == s.driver }?.medianPercentile(s.key)
        }
        let numbers = steps.flatMap { step in series.compactMap { value(step, $0)?.micros } }.filter { $0 > 0 && $0.isFinite }
        guard steps.count > 0, let low = numbers.min(), let high = numbers.max() else { return "" }

        let width = 640.0, height = 260.0
        let left = 88.0, right = 28.0, top = 24.0, bottom = 44.0
        let lo = floor(log10(low)), hi = max(ceil(log10(high)), lo + 1)
        func y(_ micros: Double) -> Double { top + (hi - log10(micros)) / (hi - lo) * (height - top - bottom) }
        let span = width - left - right
        func x(_ index: Int) -> Double { steps.count == 1 ? left + span / 2 : left + Double(index) / Double(steps.count - 1) * span }

        var svg = "<figure class=\"chart\"><svg viewBox=\"0 0 \(Int(width)) \(Int(height))\" role=\"img\" aria-label=\"p50 and p99 latency per rate step, Swift and .NET, log scale\">\n"
        for exponent in stride(from: Int(lo), through: Int(hi), by: 1) {
            let micros = pow(10, Double(exponent))
            let yy = fixed(y(micros), 1)
            svg += "<line class=\"grid\" x1=\"\(fixed(left, 0))\" x2=\"\(fixed(width - right, 0))\" y1=\"\(yy)\" y2=\"\(yy)\"/>"
            svg += "<text class=\"axis\" x=\"\(fixed(left - 8, 0))\" y=\"\(yy)\" text-anchor=\"end\" dominant-baseline=\"middle\">\(esc(latencyText(micros)))</text>\n"
        }
        for (index, step) in steps.enumerated() {
            svg += "<text class=\"axis\" x=\"\(fixed(x(index), 1))\" y=\"\(fixed(height - 14, 0))\" text-anchor=\"middle\">\(esc(rateText(step.rate)))</text>\n"
        }
        var anyHollow = false, anyCensored = false
        for s in series {
            var segment: [String] = []
            var paths: [[String]] = []
            var marks = ""
            let color = s.driver == CellAnalysis.swift ? "swift" : "dotnet"
            for (index, step) in steps.enumerated() {
                let label = "\(clientName(s.driver)) \(s.name) at \(rateText(step.rate))"
                switch value(step, s) {
                case let .micros(v)?:
                    let point = "\(fixed(x(index), 1)),\(fixed(y(Double(max(v, 1))), 1))"
                    segment.append(point)
                    let hollow = s.dashed && !(step.clients.first { $0.driver == s.driver }?.sustained ?? true)
                    anyHollow = anyHollow || hollow
                    marks += "<circle class=\"\(color)\(hollow ? " hollow" : "")\" cx=\"\(fixed(x(index), 1))\" cy=\"\(fixed(y(Double(max(v, 1))), 1))\" r=\"4\"><title>\(esc(label)): \(hollow ? "≥ " : "")\(esc(latencyText(Double(v))))\(hollow ? " (censored: step not sustained)" : "")</title></circle>"
                case .censored?:
                    anyCensored = true
                    if !segment.isEmpty { paths.append(segment); segment = [] }
                    let cx = x(index) + (s.driver == CellAnalysis.swift ? -5 : 5)
                    marks += "<path class=\"\(color)\" d=\"M\(fixed(cx - 5, 1)),\(fixed(top - 4, 1)) L\(fixed(cx + 5, 1)),\(fixed(top - 4, 1)) L\(fixed(cx, 1)),\(fixed(top - 13, 1)) Z\"><title>\(esc(label)): &gt; deadline</title></path>"
                case nil:
                    if !segment.isEmpty { paths.append(segment); segment = [] }
                }
            }
            if !segment.isEmpty { paths.append(segment) }
            for path in paths where path.count > 1 {
                svg += "<polyline class=\"line \(color)\(s.dashed ? " dashed" : "")\" points=\"\(path.joined(separator: " "))\"/>"
            }
            svg += marks + "\n"
        }
        svg += "</svg>\n"
        svg += "<figcaption><span class=\"key swift\"></span> Swift <span class=\"key dotnet\"></span> .NET · solid p50, dashed p99 · \(anyCensored ? "▲ &gt; deadline (censored) · " : "")\(anyHollow ? "<span class=\"key hollow\"></span> hollow: p99 of a step the client did not sustain (censored, a lower bound) · " : "")x: target rate (\(esc(rateUnit(a.result.cell.kind)))), y: latency, log scale · medians over valid rounds; exact values in the table below</figcaption></figure>\n"
        return svg
    }

    // MARK: - Formatting (never prints NaN or infinity)

    static func esc(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(character)
            }
        }
        return out
    }

    private static func anchor(_ id: String) -> String {
        "cell-" + String(id.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "-" })
    }

    /// `value` with `digits` decimals, or "—" when it is not finite.
    static func fixed(_ value: Double, _ digits: Int) -> String {
        guard value.isFinite else { return "—" }
        return String(format: "%.\(digits)f", value)
    }

    /// Integer with thousands separators ("1,234,567"), locale-independent.
    static func grouped(_ value: Int) -> String {
        let digits = String(value.magnitude)
        var out = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { out += "," }
            out.append(character)
        }
        return value < 0 ? "-" + out : out
    }

    private static func count(_ value: Double?) -> String {
        guard let value, value.isFinite, abs(value) < 1e15 else { return "—" }
        return grouped(Int(value.rounded()))
    }

    /// A rate: whole numbers grouped, fractions with up to two decimals.
    static func rateText(_ rate: Double) -> String {
        guard rate.isFinite, abs(rate) < 1e15 else { return "—" }
        if abs(rate) >= 100 || rate == rate.rounded() { return grouped(Int(rate.rounded())) }
        return fixed(rate, abs(rate) >= 10 ? 1 : 2)
    }

    static func latencyText(_ micros: Double) -> String {
        guard micros.isFinite else { return "—" }
        if micros < 1000 { return "\(Int(micros.rounded())) µs" }
        if micros < 1_000_000 { return "\(fixed(micros / 1000, micros < 100_000 ? 1 : 0)) ms" }
        return "\(fixed(micros / 1_000_000, 2)) s"
    }

    /// A percentile cell, already HTML: "&gt; deadline" when censored, "—" when there is no valid trial.
    /// With `lowerBound` (an upper percentile of an unsustained step) a number is shown as "≥ value", censored.
    private static func latency(_ value: PercentileValue?, lowerBound: Bool = false) -> String {
        switch value {
        case let .micros(v)?:
            lowerBound
                ? "<span class=\"censored\" title=\"censored: step not sustained\">≥ \(esc(latencyText(Double(v))))</span>"
                : esc(latencyText(Double(v)))
        case .censored?: "&gt; deadline"
        case nil: "—"
        }
    }

    private static func duration(seconds: Double) -> String {
        guard seconds.isFinite else { return "—" }
        return seconds < 1 ? "\(fixed(seconds * 1000, seconds < 0.01 ? 2 : 1)) ms" : "\(fixed(seconds, 1)) s"
    }

    private static func megabytes(_ bytes: Double) -> String {
        bytes.isFinite ? "\(fixed(bytes / 1_000_000, 1)) MB" : "—"
    }

    private static func headroomBadge(_ state: HeadroomState, empty: Bool) -> String {
        if empty { return "—" }
        switch state {
        case .ok: return "<span class=\"badge good\">ok</span>"
        case .systemLimited: return "<span class=\"badge bad\">system-limited</span>"
        case .unavailable: return "<span class=\"badge muted\">unavailable</span>"
        }
    }

    static func clientName(_ driver: String) -> String {
        switch driver {
        case CellAnalysis.swift: "Swift"
        case CellAnalysis.dotnet: ".NET"
        default: driver
        }
    }

    private static func kindTitle(_ kind: ScenarioKind) -> String {
        switch kind {
        case .appendLatency: "Append latency (batch 1)"
        case .appendThroughput: "Append throughput (batch 50)"
        case .rebuild: "Rebuild (whole-stream read, JSON decoded)"
        case .persistentSubscription: "Persistent subscription on $ce- (ack per event)"
        case .catchUp: "Catch-up subscription on $ce-"
        }
    }

    private static func rateUnit(_ kind: ScenarioKind) -> String {
        switch kind {
        case .appendLatency: "appends/s"
        case .appendThroughput: "batches of 50 events/s"
        case .rebuild: "whole-stream reads/s"
        case .persistentSubscription, .catchUp: "events written/s"
        }
    }

    // MARK: - Style

    private static let css = """
    :root{color-scheme:light;--bg:#fcfcfb;--surface:#f3f2ef;--text:#0b0b0b;--text2:#52514e;--muted:#6b6a66;--line:#dddcd7;--grid:#e6e5e0;
    --swift:#2a78d6;--dotnet:#eb6834;--good-bg:#e3f4ea;--good:#1d6b3c;--bad-bg:#fbe5e3;--bad:#a2271c;--warn-bg:#fdf1d8;--warn:#7a5200;--chip:#ecebe7}
    @media (prefers-color-scheme: dark){:root:not([data-theme="light"]){color-scheme:dark;--bg:#1a1a19;--surface:#242422;--text:#f0efec;--text2:#c3c2b7;--muted:#a3a29a;--line:#3a3a37;--grid:#2e2e2b;
    --swift:#3987e5;--dotnet:#d95926;--good-bg:#173a26;--good:#8fd6a8;--bad-bg:#46201c;--bad:#f2a49b;--warn-bg:#3f3214;--warn:#f0cd7a;--chip:#2e2e2b}}
    :root[data-theme="dark"]{color-scheme:dark;--bg:#1a1a19;--surface:#242422;--text:#f0efec;--text2:#c3c2b7;--muted:#a3a29a;--line:#3a3a37;--grid:#2e2e2b;
    --swift:#3987e5;--dotnet:#d95926;--good-bg:#173a26;--good:#8fd6a8;--bad-bg:#46201c;--bad:#f2a49b;--warn-bg:#3f3214;--warn:#f0cd7a;--chip:#2e2e2b}
    *{box-sizing:border-box}
    body{margin:0;background:var(--bg);color:var(--text);font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif}
    main{max-width:1100px;margin:0 auto;padding:24px 16px 64px}
    h1{font-size:1.6rem;line-height:1.25;margin:0 0 8px}
    h2{font-size:1.25rem;margin:32px 0 6px}
    h3{font-size:1.02rem;margin:22px 0 6px}
    p,li{color:var(--text2)} strong,em{color:var(--text)}
    .lede{max-width:72ch}
    .guide ul,.fairness{padding-left:20px;max-width:80ch} .guide li{margin:4px 0}
    .fairness{font-size:.9rem}
    .cells ul{list-style:none;padding:0;display:flex;flex-wrap:wrap;gap:6px 14px}
    a{color:var(--swift)}
    section.cell{border-top:1px solid var(--line);margin-top:32px}
    .facts,.caption,.muted,figcaption{color:var(--muted);font-size:.88rem}
    .alert{background:var(--bad-bg);color:var(--bad);padding:8px 12px;border-radius:6px}
    .alert strong{color:var(--bad)}
    .note{background:var(--warn-bg);color:var(--warn);padding:8px 12px;border-radius:6px}
    .note strong{color:var(--warn)}
    .scroll{overflow-x:auto;max-width:100%;-webkit-overflow-scrolling:touch}
    table{border-collapse:collapse;font-size:.88rem;min-width:100%}
    th,td{padding:5px 8px;border-bottom:1px solid var(--line);text-align:left;vertical-align:top;white-space:nowrap}
    thead th{color:var(--muted);font-weight:600;border-bottom:1px solid var(--muted)}
    tbody th{font-weight:600}
    td.num{text-align:right;font-variant-numeric:tabular-nums}
    .ratios td:nth-child(2){white-space:normal;min-width:14em}
    .badge{display:inline-block;padding:0 7px;border-radius:9px;font-size:.8rem;background:var(--chip);color:var(--text2)}
    .badge.good{background:var(--good-bg);color:var(--good)} .badge.bad{background:var(--bad-bg);color:var(--bad)} .badge.warn{background:var(--warn-bg);color:var(--warn)}
    figure.chart{margin:12px 0;background:var(--surface);border-radius:8px;padding:8px}
    figure.chart svg{width:100%;max-width:760px;height:auto;display:block}
    .grid{stroke:var(--grid);stroke-width:1}
    .axis{fill:var(--muted);font-size:18px}
    .line{fill:none;stroke-width:2} .line.dashed{stroke-dasharray:6 4}
    .line.swift{stroke:var(--swift)} .line.dotnet{stroke:var(--dotnet)}
    circle.swift,path.swift{fill:var(--swift);stroke:var(--surface);stroke-width:2} circle.dotnet,path.dotnet{fill:var(--dotnet);stroke:var(--surface);stroke-width:2}
    circle.hollow{fill:var(--surface);stroke-width:2} circle.hollow.swift{stroke:var(--swift)} circle.hollow.dotnet{stroke:var(--dotnet)}
    .key.hollow{width:9px;height:9px;border-radius:50%;border:2px solid var(--muted);background:transparent}
    .censored{color:var(--muted)}
    .key{display:inline-block;width:14px;height:3px;vertical-align:middle;margin-left:6px} .key.swift{background:var(--swift)} .key.dotnet{background:var(--dotnet)}
    details{margin:12px 0} summary{cursor:pointer;color:var(--text2)}
    details code{white-space:pre-wrap;word-break:break-word;font-size:.82rem}
    dl{display:grid;grid-template-columns:minmax(8em,max-content) 1fr;gap:2px 14px;font-size:.85rem}
    dt{color:var(--muted)} dd{margin:0;word-break:break-all;color:var(--text2)}
    """
}
