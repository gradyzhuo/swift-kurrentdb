# Live benchmarks against a real KurrentDB server — design

Status: draft, open questions resolved, awaiting approval · Date: 2026-10-25

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
- Image pinned to an exact tag (target: the current 26.2.x) and recorded in every report.
  It must start on a GitHub runner without a license key; if 26.2 needs one for the
  features used here, fall back to the newest version that does not, and say so.
- TLS and authentication on for the main runs (that is what production looks like, and
  each SDK's TLS/HTTP/2 stack is part of its cost). One extra run with TLS off isolates
  TLS cost.
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
   - Writer appends to category A at a fixed rate; consumer group handles and acks.
   - Measure append-to-delivery latency, ack throughput, and several consumers with
     RoundRobin.
4. **Catch-up subscription (secondary)**
   - On `$ce-<Category>`, not `$all`.
   - Catch-up throughput from the start over 1,000,000 pre-seeded events, and live
     append-to-delivery latency once caught up. No multi-consumer variants.

All clients read identical pre-seeded data, written by one seeding tool.

### Clients and reference points (phase 1)

- **Swift** — this SDK, built from the commit under test.
- **.NET** — `KurrentDB.Client`, pinned exact NuGet version.
- **ghz** — sends byte-identical gRPC messages with no SDK on top: the floor.

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
- Co-locating server and client on 4 vCPU shares memory bandwidth and L3 cache even with
  CPU pinning; interleaving keeps the comparison fair but absolute numbers are
  conservative.
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
