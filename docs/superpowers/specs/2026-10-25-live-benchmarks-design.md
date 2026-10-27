# Live benchmarks against a real KurrentDB server — design

Status: approved 2026-10-26 (builder check + 4 Codex rounds, clean) · Date: 2026-10-25

## Intent

swift-kurrentdb wants evidence that it is fit for production, using the official
.NET client (`KurrentDB.Client`) as the yardstick, and evidence that Swift is not
slow. The maintainer's words: "check whether my SDK reaches the official level, as
an indicator that it can be used in production", and "I only use the official client
as the standard; I also want to show Swift is not slow".

The existing `Benchmarks/OfflineBenchmarks` suite measures client-side code paths
with no server. This design adds benchmarks that talk to a real KurrentDB server over
gRPC, in two layers:

- **Trend layer** — the SDK compared with its own history, nightly, Swift only.
- **Comparison layer** — the SDK compared with other clients on the same scenarios,
  run on demand, producing a public report.

## Goals

1. Show that under normal load the SDK is not the bottleneck: at fixed common rates,
   Swift's p50 and p99 latency are within a multiple of .NET's (target 1.2×, to be
   confirmed against real data), and its client CPU and memory per operation are
   comparable.
2. Catch performance regressions in the SDK over time (trend layer).
3. Make every number reproducible by anyone from a public workflow and committed raw
   data.

## Non-goals (for now)

- **Measuring the server's ceiling.** It needs server and load generators on separate
  machines, which GitHub-hosted runners cannot provide. Deferred; see "Later".
- Proving Swift is *faster* than .NET. Parity is the bar.
- Error paths, cold start, failover, and a one-hour soak test (phase 3).
- Go, Rust (phase 2), Python, Node.js (phase 4).

## Anti-goals

- **No private infrastructure.** Everything runs on GitHub-hosted runners. No
  hostnames, IPs, usernames or internal topology of any private machine may appear in
  the repository, workflows, results or reports.
- No CI-failing latency thresholds from the live suite: runner CPUs differ by up to
  63% between runs, so a hard threshold would fail main on noise.
- No tuning only the Swift client. If anything is tuned, every client is tuned the same
  way, from its own documentation, and the tuning is disclosed.

## Constraints

- The repository is public and owned by a personal account, so only standard
  GitHub-hosted runners are available (`ubuntu-latest`: 4 vCPU, 16 GB). Larger runners
  need an organization on a Team or Enterprise plan.
- Jobs cannot reach each other over the network, so the server and the clients run on
  the same VM.
- Runner CPU models change between runs (seen: EPYC 9V45, EPYC 9V74, Xeon 8573C) and
  latency differs by up to 63%. Absolute numbers from different runs are not
  comparable; ratios within one job are.
- Allocation counts of concurrent code on the 4 vCPU runner are bimodal; they cannot be
  used as thresholds.
- The orchestrator and the Swift driver are written in Swift, to keep the repository
  in one language (maintainer's decision).
- Live benchmark code must not add dependencies to the root `Package.swift`.
- Code comments and documentation are in English.

## Decisions made with the maintainer

### Server

- Single node. From 26.2 onward single-node deployments are the main use case.
- Image pinned to an exact 26.2.x tag, its digest recorded in every report. 26.2
  single-node deployments need no license key.
- TLS and authentication on for the main runs (that is what production looks like, and
  each SDK's TLS/HTTP/2 stack is part of its cost). Certificates come from
  `es-gencert-cli`, as `server/docker-compose.yaml` already does.
- One extra run with TLS off **and authentication still on** isolates TLS cost. It must
  not use `Insecure` mode, which also disables authentication and would confound the
  comparison; use the 26.2 options that disable only TLS (documented as `DisableTls`
  with a `ClusterSecret`; the builder confirms them against the 26.2 docs).
- `$by_category` system projection enabled (subscription scenarios read `$ce-` streams).
- Fresh data directory per job.

### Workload shape (from a real production workload)

A sample of a production KurrentDB (≈40k events, ≈104k streams, ≈200 categories) gave:
event data p50 282 B, p90 679 B, p99 954 B, max 3.1 KB, JSON; metadata p50 53 B;
average stream length per category p50 34, p90 ≈640, max ≈8.9k; all persistent
subscriptions are on `$ce-<Category>` streams; read models are built by server-side
projections, and persistent subscriptions carry cross-aggregate communication.
Only these aggregate numbers go into the repository.

### Phase 1 scenarios

Common: JSON events of **300 B (main), 1 KB and 4 KB** (4 KB kept for other adopters'
needs), metadata 60 B.

1. **Append**
   - Latency run: batch size 1, a stream picked uniformly at random from 100,000 streams,
     `expectedRevision = .any`.
   - Throughput run: batch size 50, otherwise the same.
   - Optimistic-concurrency contention is an error path, phase 3.
2. **Rebuild aggregate** (read a whole stream forward)
   - Pre-seeded streams of length 10, 100, 1,000 and 10,000, 100 streams each.
   - Measure time to read a whole stream and events read per second.
   - Events are JSON-decoded, not just received as bytes.
3. **Persistent subscription (primary subscription scenario)**
   - Group on `$ce-<Category>`, `resolveLinkTos` on, ack on receipt.
   - The writer runs inside the driver under test, using that same SDK, and appends to
     the category on an open-loop schedule. Both clients therefore pay for writing and
     consuming in one process, symmetrically, and the reported CPU covers both.
   - Delivery latency is measured from the append's **scheduled** time to receipt.
   - Two throughput numbers, never conflated: the rate at which the client hands acks
     to its transport (Swift's `ack()` only enqueues locally), and **acknowledged
     progress observed by the server** — the headline. The builder verifies which field
     of the subscription info API counts acknowledged (not merely delivered) events,
     and documents it; the orchestrator polls it.
   - At the end of the window a bounded drain waits for acknowledged progress to reach
     the number of events written; the shortfall is reported.
   - The driver counts unique deliveries and redeliveries (by event id) separately;
     redeliveries are reported and never counted as throughput.
   - Several consumers with RoundRobin is an appendix variant.
4. **Catch-up subscription (secondary)**
   - On `$ce-<Category>`, not `$all`.
   - **Link resolution explicitly enabled for every client.** `$ce-` streams hold link
     events, and the Swift SDK defaults to not resolving links; without this every
     event size would transfer the same small links.
   - Catch-up throughput from the start over 1,000,000 pre-seeded events, and live
     append-to-delivery latency once caught up. No multi-consumer variants.

All clients read identical pre-seeded data, written by one seeding tool. Every
subscription and read scenario validates received event counts and payload sizes
against what was seeded; a mismatch fails the trial.

### Clients and reference points (phase 1)

- **Swift** — this SDK, built from the commit under test.
- **.NET** — `KurrentDB.Client`, pinned exact NuGet version.
- **ghz** — sends byte-identical gRPC messages with no SDK on top. It is a separately
  labelled **transport reference**, not a latency floor: ghz times from RPC initiation,
  not from scheduled send time, runs on the Go runtime, and skips JSON decoding, so its
  latency is never put in a ratio with the SDKs. Its achieved rate and server-side
  behaviour at each step are shown beside them for orientation.

No grpc-swift-only driver in the live suite (maintainer's decision): the generated
client is not exported from the root package, and the offline `GRPC/*` group of PR #182
already separates grpc-swift cost from SDK cost.

### Load model

- Open loop at fixed rates, ramping upward; latency measured from each request's
  scheduled send time (no coordinated omission).
- In-flight requests capped; overflow counted as a drop.
- Per step: p50, p99, p99.9, achieved rate, errors, drops, client CPU time and RSS.
- The maximum rate one client sustains is itself a result. Issue #142 found a ceiling
  of about 100 concurrent streams per HTTP/2 connection. The report shows whatever
  ceiling each client hits; fixing it is **out of scope** and becomes separate work if
  the numbers justify it (maintainer's decision).
- Reports publish whatever the numbers are. Missing the 1.2× target blocks nothing; the
  report states it.

### Measurement rules

These close the gaps that would make percentiles or parity misleading.

- **Every scheduled operation is accounted for**: completed, failed, dropped (in-flight
  cap reached) or timed out. All clients share the same in-flight cap and per-operation
  deadline. At the end of a measured window the driver drains for a bounded time;
  anything still unfinished counts as timed out and is reported, never silently
  excluded from percentiles.
- **A step is sustained** only when the *successful* rate ≥ 99% of target, errors +
  drops + timeouts ≤ 0.1%, and the backlog does not grow over the window (exact
  thresholds are the builder's, but fixed before the first published run; they are
  fixed in `Benchmarks/Live/docs/driver-contract.md` rule 11 for the backlog and in
  `EvaluationThresholds` for the rate and loss criteria). Latency
  from a step that is not sustained is never used in a headline comparison; where it is
  shown, its upper percentiles are marked as censored.
- **Percentiles are ranked over all scheduled attempts**, not over successes only.
  A failed, dropped or timed-out attempt counts as a latency of +∞ (worse than the
  deadline). Any percentile that lands among those attempts is reported as
  "> deadline" (censored) rather than as a number, on sustained steps too, so a
  permitted 0.1% loss cannot flatter p99.9.
- **Server headroom.** The orchestrator records, per step, server CPU per core (so a
  single saturated core is visible), disk latency and queue depth, disk usage, and
  `$by_category` projection backlog. Any of them crossing its limit fails the headroom
  gate. A step where the server's 2 cores are
  near saturation or the projection backlog grows is labelled **system-limited**: it is
  shown, but no SDK conclusion is drawn from it. Parity is judged only at steps both
  clients sustain with server headroom, so a saturated server cannot manufacture parity.
- **Equivalent starting state for every trial.**
  - Every client trial starts from the identical seeded database: the server is
    stopped, its data directory is restored from a snapshot taken right after seeding,
    and it is started again. Writes and index state from earlier trials therefore never
    carry over.
  - The same cache-conditioning procedure runs before every trial: after the restore,
    drop the OS page cache (`sync; echo 3 | sudo tee /proc/sys/vm/drop_caches`), start
    the server, then run the trial's warmup. No client inherits another's warm cache.
  - Warmup uses separate streams/categories from the measured data, so it cannot consume
    or pre-cache the measured corpus (notably the 1M-event catch-up corpus).
  - Each persistent subscription trial creates a fresh group; checkpoints never carry
    over between clients.
  - Before any trial, wait for `$by_category` to reach the seed's last position.
  - Between trials, drain until the server is idle (no in-flight work, projection backlog
    zero).
- **Statistics.** Each round yields one paired ratio per metric (Swift ÷ .NET, both
  measured in that round). The interval is a 95% confidence interval over the
  round-level log-ratios. Minimum 5 rounds for headline cells, 3 for appendix cells.
  Every ratio is oriented so that **higher means Swift is worse**: Swift ÷ .NET for
  lower-is-better metrics (latency, CPU per operation, RSS), .NET ÷ Swift for
  higher-is-better metrics (throughput). Verdict against 1.2×: **meets** when the upper
  bound ≤ 1.2, **misses** when the lower bound > 1.2, otherwise **inconclusive**, and
  the report says which.

### Fairness

- Headline results use each SDK's **default settings**.
- An appendix may show tuned results: only knobs in each client's official docs,
  applied to every client, disclosed.
- 30 s warmup at the step's load before measuring (the .NET JIT/tiered compilation needs
  it). Cold start is measured separately in phase 3.

### Comparison layer on GitHub Actions

- One job, one VM. Server container pinned with `--cpuset-cpus` to 2 cores; the client
  under test pinned with `taskset` to the other 2.
- Clients interleaved within the job in rotated order (ABC, BCA, CAB, …) over several
  rounds to cancel VM drift.
- Headline metric is the **ratio** Swift ÷ .NET with a confidence interval from the
  rounds, plus client CPU time per 1,000 operations and RSS. Absolute numbers are shown
  with the runner's CPU model.
- Network is loopback: the report states that real network effects are not included.
- Triggered by `workflow_dispatch` and by release tags.
- **Resource budget.** A standard runner has about 14 GB of free disk and a 6-hour job
  limit; 4 KB appends at 100 batches/s add about 1.2 GB per minute. Each cell has a
  fixed schedule and a disk budget (seed size, writes, builds, measurement time) that
  fits both; the server data directory is recreated between cells, and the orchestrator
  checks free space before each step and stops the cell, recording why, rather than
  running out mid-step.
- **Reproducibility metadata** archived with every result bundle: the resolved
  dependency graph of `Benchmarks/Live` (its `Package.resolved` is committed, overriding
  the repository-wide `.gitignore` entry), the resolved .NET dependency graph (lock
  file), the SDK and harness commit SHAs, Swift toolchain, .NET runtime and
  `KurrentDB.Client` version, ghz version, build flags, server image digest and its
  effective configuration, the effective scenario configuration (rates, durations,
  in-flight caps, deadlines), scenario random seed, and runner image version and CPU
  model.

### Trend layer

- Nightly on main (not on every push: a live run with server start and seeding takes
  well over ten minutes).
- Swift only, a fixed moderate rate per scenario, no rate ramp.
- Same runner class, results to the existing Bencher project with the same t-test
  policy as the offline suite (alert only after 10 runs of history), no CI-failing
  thresholds. Lives in or next to `.github/workflows/benchmarks.yml`.

### Code layout

```
Benchmarks/Live/                 # its own SwiftPM package; root Package.swift untouched
├── scenarios/                   # scenario definitions (YAML), shared by all clients
├── drivers/
│   ├── swift/                   # depends on the repo root by path (commit under test)
│   ├── dotnet/                  # console app on KurrentDB.Client
│   └── ghz/                     # config only
├── orchestrator/                # Swift executable that runs a whole job
└── results/                     # raw histograms + JSON, committed
```

**Driver contract** (every language implements it; keep it small):
input — scenario file, target rate, duration, connection string; behaviour — open-loop
scheduling inside the driver; output — an HdrHistogram file plus one JSON line with
achieved rate, errors, drops, CPU time and RSS.

**Orchestrator**: starts the server container, seeds data, runs the rate steps with
clients interleaved, collects results, and renders the report. Histograms via ordo-one
`package-histogram`; the report is one self-contained HTML file with inline SVG charts.

## Calls I made (not discussed with the maintainer)

- **Splitting the comparison run.** The full phase 1 matrix does not fit one 6-hour job.
  The comparison workflow runs one job per (scenario × event size) cell, in parallel;
  every job runs all clients interleaved, so each ratio still comes from one VM. Tiers:
  - Headline: 300 B, TLS on, full rate ramp, all rounds.
  - Appendix: 1 KB, 4 KB and the TLS-off run use 2 rate steps (low and mid) and fewer
    rounds; multi-consumer persistent subscription is appendix too.
  The report never divides numbers from different jobs.
- **Getting results into the repo.** Workflows stay read-only, matching the existing
  policy that a person reviews numbers before they land. The comparison workflow
  uploads raw results and the HTML report as artifacts; the maintainer commits them
  under `Benchmarks/Live/results/<date>-<server version>/` in a PR, and the report is
  published on the GitHub Pages benchmarks page with a summary and link in
  BENCHMARKS.md. Nightly trend runs only upload to Bencher; they commit nothing.
- **Reference point coverage.** ghz covers append and rebuild (rebuild without JSON
  decoding, which the report states); subscriptions are
  Swift vs .NET only. ghz is wrapped by a small adapter that converts its JSON output to
  the driver contract; if its rate mode does not measure from scheduled send time, the
  report says so.
- Rotation order and number of rounds per job are left to the builder, sized to fit
  the job time limit.

## Left to the builder

- Exact rate steps per scenario on a 2-core client budget.
- Scenario file schema, CLI flags, JSON field names.
- How TLS certificates are generated in the workflow.
- Whether KurrentDB's per-RPC server metrics are usable as an extra reference point
  (unverified; check before relying on them).

## Open risks

- The 1.2× parity target is an assumption until real numbers exist.
- Co-locating server and client on 4 vCPU shares memory bandwidth, L3 cache and disk
  even with CPU pinning. The interference is not necessarily in either client's favour;
  the headroom rule above limits conclusions to steps where it is unlikely to dominate.
- PR #142 (stress-test v2, closed 2026-09-30) is superseded by this design
  (maintainer's decision). Build from scratch; its code (open-loop scheduling, HDR
  histogram, saturation detection, HTML report) may be consulted for individual pieces,
  but none of its eleven open load-model decisions bind this design.

## Later

- **Server ceiling**: separate machines (e.g. short-lived cloud VMs created and torn
  down by the workflow), multiple client processes. Needs a cloud account.
- Phase 2: Go, Rust on the same scenarios.
- Phase 3: error paths, cold start, failover (three-node 26.1; 26.2 multi-node needs a
  license), one-hour soak — Swift and .NET only.
- Phase 4: Python, Node.js — append and rebuild only.
