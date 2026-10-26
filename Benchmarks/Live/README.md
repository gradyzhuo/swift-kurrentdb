# Live benchmarks

The SDK against a real KurrentDB server, next to the official .NET client (`KurrentDB.Client`) and, for append and
rebuild, ghz as a transport reference. This directory is its own SwiftPM package (`LiveBenchmarks`); the root
`Package.swift` does not know about it. The CI side, the published report and how results land in the repository are
described in [BENCHMARKS.md](../../BENCHMARKS.md#live-benchmarks); the design is in
[docs/superpowers/specs/2026-10-25-live-benchmarks-design.md](../../docs/superpowers/specs/2026-10-25-live-benchmarks-design.md).

| Path | What it is |
|---|---|
| `config/cells.json` | Every cell (scenario x event size x TLS) with its rates, rounds and tier |
| `config/server.json` | The pinned server image (`kurrentplatform/kurrentdb:26.2.x`) |
| `config/drivers.local.json` | The clients, as commands relative to the repository root (also used by CI) |
| `drivers/swift`, `drivers/dotnet`, `drivers/ghz` | The Swift driver, the .NET driver, ghz call configs |
| `docs/driver-contract.md` | What every driver must do: command line, open loop, outputs, per-client notes |
| `orchestrator/` | `LiveOrchestrator`: runs a cell, merges cells into a results bundle and report, runs the trend |
| `Sources/LiveBenchCore` | Contract types, open loop, statistics shared by the Swift driver and the orchestrator |

## Prerequisites

- Docker (the server runs in a container; certificates are generated in one too).
- Swift 6.0 or later (CI uses 6.4).
- .NET 8 SDK, for the .NET driver.
- [ghz](https://github.com/bojand/ghz) v0.120.0 on `PATH`, for append and rebuild cells (CI installs the release
  tarball and checks its SHA-256).

## Build the drivers

Run every command from the repository root: `config/drivers.local.json` resolves its commands against the working
directory.

```bash
swift build --package-path Benchmarks/Live -c release
dotnet build Benchmarks/Live/drivers/dotnet -c Release -p:RestoreLockedMode=true
```

The first builds `LiveDriverSwift` and `LiveOrchestrator` into `Benchmarks/Live/.build/release/`. The second restores in
locked mode, so a restore that would drift from `drivers/dotnet/packages.lock.json` fails instead.

## Run one cell

```bash
Benchmarks/Live/.build/release/LiveOrchestrator run-cell \
  --cell persistent-300-tls \
  --drivers Benchmarks/Live/config/drivers.local.json \
  --out /tmp/live-dry/persistent-300-tls \
  --smoke
```

`--smoke` keeps one round, the cell's first rate, and 5 s warmup and measure windows: a check that every client runs,
never a result. Without it the cell runs its full schedule from `cells.json` (a headline cell takes hours). The
output directory gets `cell-result.json` (rewritten after every trial) and each trial's files under `trials/`.

Useful options (`LiveOrchestrator run-cell --help` lists them all):

- `--work <dir>`: the server's work directory (certificates, data, snapshot, logs); a temporary directory by default.
  On macOS pass a directory outside `/var/folders` (for example under `/tmp`): with the default one the server failed
  to restart from its snapshot on Docker for Mac (`/var/lib/kurrentdb already exists`).
- `--server-cpus` (default `0,1`) and `--driver-cpus` (default `2,3`): the server container is pinned with
  `--cpuset-cpus`, each driver with `taskset` (Linux only). On Linux the server uses the host network.

Between trials the orchestrator drops the page cache with `sudo -n` on Linux (a no-op elsewhere). Server headroom
(CPU per core, disk await and queue depth) is read from `/proc`, so on macOS it is unavailable and the report says so.

## Merge cells into a report

```bash
Benchmarks/Live/.build/release/LiveOrchestrator merge --in /tmp/live-dry --out /tmp/live-results
```

It finds every `cell-result.json` under `--in` and writes the bundle
`<out>/<YYYY-MM-DD>-<server version>/`: each cell's results, `metadata.json` (toolchains, client versions, server
image digest, runner image and CPU model, never a host name), the resolved Swift and .NET dependency graphs, and
`report.html`. It prints the report's path.

## Trend (Swift only)

```bash
Benchmarks/Live/.build/release/LiveOrchestrator trend \
  --drivers Benchmarks/Live/config/drivers.local.json \
  --out /tmp/live-trend
```

Every headline cell at one moderate rate, one round, with the Swift driver only. It writes each cell's results and
`bmf.json` (Bencher Metric Format, latency in nanoseconds), which the nightly workflow uploads to Bencher.

## Tests

```bash
swift test --package-path Benchmarks/Live
LIVE_BENCH_DOCKER=1 swift test --package-path Benchmarks/Live
```

Tests that start a server container or run the drivers against one are enabled only with `LIVE_BENCH_DOCKER=1`. The
.NET parity and conformance tests need `dotnet` on `PATH`; they build the .NET driver themselves in locked mode.

## Reading the numbers

Each client runs with its SDK's default client settings, and the report states where those defaults differ. From the
driver contract (`docs/driver-contract.md`, ".NET notes"):

- A persistent subscription consumer gets the client's default buffer: 10 events in .NET, 1000 in the Swift SDK.
- The .NET client needs a separate persistent subscriptions client, so a .NET persistent subscription trial uses two
  gRPC channels; the Swift driver uses one client.
- The .NET thread pool's default spin before sleeping costs process CPU even with a no-op operation, and that CPU is
  counted in the client's CPU figures.
- Each driver's no-op harness floor is recorded in the contract; latencies close to it say more about the harness than
  the client.
