// The .NET client under test: KurrentDB.Client (exact version pinned in LiveDriver.DotNet.csproj) implementing
// docs/driver-contract.md. `run` executes one trial, `version` reports the pinned client version, `floor` measures the
// harness's no-op floor (contract rule 10).
//
//   dotnet LiveDriver.DotNet.dll run --scenario <effective.json> --connection <connection string> --out <dir>
//   dotnet LiveDriver.DotNet.dll version
//   dotnet LiveDriver.DotNet.dll floor --rate <ops/s> [--seconds <s>] [--warmup <s>]

using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.Json;
using KurrentDB.Client;
using LiveDriver;

try
{
    return args switch
    {
        ["run", .. var rest] => await RunCommand(Options(rest, "scenario", "connection", "out")),
        ["version"] => VersionCommand(),
        ["floor", .. var rest] => await FloorCommand(Options(rest, "rate", "seconds", "warmup")),
        _ => throw new UsageException(
            "usage: LiveDriver.DotNet run --scenario <file> --connection <string> --out <dir> | version | floor --rate <ops/s> [--seconds <s>] [--warmup <s>]"),
    };
}
catch (UsageException e)
{
    Console.Error.WriteLine($"Error: {e.Message}");
    return 64; // EX_USAGE, as the Swift driver's argument parser
}
catch (Exception e)
{
    Console.Error.WriteLine($"Error: {e}");
    return 1;
}

static async Task<int> RunCommand(Dictionary<string, string> options)
{
    string scenarioPath = Required(options, "scenario"), connection = Required(options, "connection"), outPath = Required(options, "out");
    EffectiveScenario scenario;
    try
    {
        scenario = JsonSerializer.Deserialize<EffectiveScenario>(File.ReadAllBytes(scenarioPath), Json.Options)
            ?? throw new UsageException("empty scenario");
    }
    catch (JsonException e)
    {
        throw new UsageException($"cannot read scenario {scenarioPath}: {e.Message}");
    }
    scenario.Validate();
    Directory.CreateDirectory(outPath);

    // Default client settings from the connection string, no tuning.
    await using var clients = new Clients(KurrentDBClientSettings.Create(connection));

    Log.Info($"{scenario.CellId}: {Json.KindName(scenario.Kind)} at {scenario.Rate}/s, warmup {scenario.WarmupSeconds} s, measure {scenario.MeasureSeconds} s");
    var trial = scenario.Kind switch
    {
        ScenarioKind.AppendLatency or ScenarioKind.AppendThroughput => await Scenarios.RunAppend(scenario, clients),
        ScenarioKind.Rebuild => await Scenarios.RunRebuild(scenario, clients),
        ScenarioKind.PersistentSubscription => await Scenarios.RunPersistentSubscription(scenario, clients),
        ScenarioKind.CatchUp => await Scenarios.RunCatchUp(scenario, clients),
        _ => throw new UsageException($"unknown kind {scenario.Kind}"),
    };

    var result = trial.Result(scenario);
    File.WriteAllBytes(Path.Combine(outPath, "result.json"), JsonSerializer.SerializeToUtf8Bytes(result, Json.Indented));
    File.WriteAllBytes(Path.Combine(outPath, "histogram.json"), JsonSerializer.SerializeToUtf8Bytes(HistogramFile.From(trial.Recorder.Histogram), Json.Indented));
    Log.Info($"done: {result.Succeeded}/{result.Scheduled} succeeded, {result.Failed} failed, {result.Dropped} dropped, {result.TimedOut} timed out");
    return 0;
}

static int VersionCommand()
{
    string clientVersion = typeof(LiveDriver.Log).Assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
        .FirstOrDefault(a => a.Key == "KurrentDBClientVersion")?.Value
        ?? throw new InvalidOperationException("the build did not embed KurrentDBClientVersion");
    var version = new DriverVersion("dotnet", clientVersion, RuntimeInformation.FrameworkDescription);
    Console.Out.WriteLine(JsonSerializer.Serialize(version, Json.Options));
    return 0;
}

/// The harness floor: the same open loop with an operation that returns immediately, after a warmup window at the same
/// rate (the JIT compiles the loop during warmup, as in a trial). Prints one JSON line.
static async Task<int> FloorCommand(Dictionary<string, string> options)
{
    double rate = double.Parse(Required(options, "rate"), System.Globalization.CultureInfo.InvariantCulture);
    double seconds = options.TryGetValue("seconds", out var s) ? double.Parse(s, System.Globalization.CultureInfo.InvariantCulture) : 5;
    double warmup = options.TryGetValue("warmup", out var w) ? double.Parse(w, System.Globalization.CultureInfo.InvariantCulture) : 2;
    OpenLoopConfig Config(double length) => new(rate, (long)(length * 1e9), 256, 5_000_000_000, 1_000_000_000);
    static Task<long?> NoOp(int index, CancellationToken token) => Task.FromResult<long?>(null);
    if (warmup > 0) await OpenLoop.Run(Config(warmup), NoOp);
    var before = ProcessUsage.Current();
    var r = await OpenLoop.Run(Config(seconds), NoOp);
    var after = ProcessUsage.Current();
    Console.Out.WriteLine(JsonSerializer.Serialize(new
    {
        rate,
        seconds,
        scheduled = r.Scheduled,
        succeeded = r.Succeeded,
        p50Micros = r.Histogram.GetValueAtPercentile(50),
        p99Micros = r.Histogram.GetValueAtPercentile(99),
        p999Micros = r.Histogram.GetValueAtPercentile(99.9),
        maxMicros = r.Histogram.GetValueAtPercentile(100),
        cpuSeconds = (after.User - before.User) + (after.System - before.System),
        runtime = RuntimeInformation.FrameworkDescription,
    }, Json.Options));
    return 0;
}

static Dictionary<string, string> Options(string[] args, params string[] known)
{
    var options = new Dictionary<string, string>();
    for (int i = 0; i < args.Length; i++)
    {
        string name = args[i].StartsWith("--") ? args[i][2..] : throw new UsageException($"unexpected argument {args[i]}");
        if (!known.Contains(name)) throw new UsageException($"unknown option --{name}");
        if (i + 1 >= args.Length) throw new UsageException($"missing value for --{name}");
        options[name] = args[++i];
    }
    return options;
}

static string Required(Dictionary<string, string> options, string name) =>
    options.TryGetValue(name, out var value) ? value : throw new UsageException($"missing --{name}");

namespace LiveDriver
{
    static class Log
    {
        /// Progress on stdout, one flushed write per line (Console.Out auto-flushes), so a killed driver's log is
        /// complete. The orchestrator reads only the output files, the marker and the stderr tail.
        public static void Info(string message) => Console.Out.WriteLine($"[LiveDriver.DotNet] {message}");

        /// The driver contract's measure-start marker: the exact line `LIVE_BENCH_MEASURE_START` on stderr (auto-flushed,
        /// so unbuffered), written immediately before the measure window's open loop starts.
        public static void MarkMeasureStart() => Console.Error.WriteLine("LIVE_BENCH_MEASURE_START");
    }
}
