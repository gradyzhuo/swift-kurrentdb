// The data side of docs/driver-contract.md: the scenario the driver reads, the files it writes, the seeded draws and
// the event bytes. Each type mirrors its Swift reference in Sources/LiveBenchCore (named next to it).

using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using HdrHistogram;

namespace LiveDriver;

/// Read with `JsonStringEnumConverter` and a camel-case policy: `appendLatency`, ..., `catchUp`.
enum ScenarioKind
{
    AppendLatency,
    AppendThroughput,
    Rebuild,
    PersistentSubscription,
    CatchUp,
}

/// `EffectiveScenario` (Scenario.swift). Unknown fields are ignored; absent optional fields are null; a missing
/// non-optional field fails deserialization (`required`), as Swift's decoder does.
sealed class EffectiveScenario
{
    public required string CellId { get; set; }
    public required ScenarioKind Kind { get; set; }
    public required int EventSize { get; set; }
    public required int MetadataSize { get; set; }
    public required int BatchSize { get; set; }
    public required int StreamCount { get; set; }
    public required string StreamPrefix { get; set; }
    public required string Category { get; set; }
    public string? GroupName { get; set; }
    public int? Consumers { get; set; }
    public int? StreamLength { get; set; }
    public List<string>? RebuildStreams { get; set; }
    public int? CatchUpExpectedEvents { get; set; }
    public required double Rate { get; set; }
    public required double WarmupSeconds { get; set; }
    public required double MeasureSeconds { get; set; }
    public required double DrainSeconds { get; set; }
    public required int DeadlineMillis { get; set; }
    public required int InFlightCap { get; set; }
    public required ulong Seed { get; set; }

    /// Rejects scenarios the driver cannot run as the contract describes (exit non-zero before connecting), like the
    /// Swift driver's `EffectiveScenario.validate()`.
    public void Validate()
    {
        if (!double.IsFinite(Rate) || Rate <= 0) throw new UsageException("rate must be positive");
        if (StreamCount <= 0 || BatchSize <= 0 || InFlightCap < 0 || DeadlineMillis <= 0)
            throw new UsageException("streamCount, batchSize and deadlineMillis must be positive, inFlightCap not negative");
        if (MetadataSize < 0 || EventSize < 0) throw new UsageException("payload sizes must not be negative");
        switch (Kind)
        {
            case ScenarioKind.AppendLatency or ScenarioKind.AppendThroughput:
                break;
            case ScenarioKind.Rebuild:
                if (RebuildStreams is not { Count: > 0 } || StreamLength is null)
                    throw new UsageException("rebuild needs rebuildStreams and streamLength");
                break;
            case ScenarioKind.PersistentSubscription:
                if (GroupName is null) throw new UsageException("persistentSubscription needs groupName");
                if (BatchSize != 1) throw new UsageException("subscription kinds append one event per operation");
                break;
            case ScenarioKind.CatchUp:
                if (CatchUpExpectedEvents is null) throw new UsageException("catchUp needs catchUpExpectedEvents");
                if (BatchSize != 1) throw new UsageException("subscription kinds append one event per operation");
                break;
        }
    }

    public OpenLoopConfig OpenLoop(double seconds) => new(
        Rate: Rate,
        DurationNanos: SecondsToNanos(seconds),
        InFlightCap: InFlightCap,
        DeadlineNanos: DeadlineMillis * 1_000_000L,
        DrainNanos: SecondsToNanos(DrainSeconds));

    static long SecondsToNanos(double seconds) => (long)Math.Round(seconds * 1e9, MidpointRounding.AwayFromZero);
}

sealed class UsageException(string message) : Exception(message);

sealed record Validation(int ExpectedEvents, int ReceivedEvents, bool PayloadSizesOk);

/// `result.json` (`TrialResult`, DriverContract.swift).
sealed record TrialResult(
    string Client,
    string CellId,
    double TargetRate,
    string Timing,
    long Scheduled,
    long Succeeded,
    long Failed,
    long Dropped,
    long TimedOut,
    double MeasuredSeconds,
    double CpuUserSeconds,
    double CpuSystemSeconds,
    ulong MaxRssBytes,
    int? AckEnqueued,
    int? UniqueDeliveries,
    int? Redeliveries,
    double? CatchUpSeconds,
    int? BacklogAtMidpoint,
    int? BacklogAtEnd,
    int? ScheduledSecondHalf,
    Validation Validation);

/// Output of `version` (`DriverVersion`).
sealed record DriverVersion(string Client, string ClientVersion, string Runtime);

static class Json
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
        PropertyNameCaseInsensitive = false,
        Converters = { new JsonStringEnumConverter(JsonNamingPolicy.CamelCase, allowIntegerValues: false) },
    };

    public static readonly JsonSerializerOptions Indented = new(Options) { WriteIndented = true };

    /// The contract's name of a kind (`appendLatency`, ...).
    public static string KindName(ScenarioKind kind) => JsonSerializer.Serialize(kind, Options).Trim('"');
}

/// The seeded random choices ("Random choices"; SeededDraw.swift): draw i of splitmix64 seeded with `seed`.
static class SeededDraw
{
    const ulong Gamma = 0x9E3779B97F4A7C15UL;

    public static ulong Draw(ulong seed, long index)
    {
        unchecked
        {
            ulong z = seed + ((ulong)index + 1) * Gamma;
            z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
            z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
            return z ^ (z >> 31);
        }
    }

    public static int Pick(ulong seed, long index, int count) => (int)(Draw(seed, index) % (ulong)count);
}

/// Event bytes ("Event bytes"; Payload.swift): `{"i":<k>,"p":"<filler>"}` of exactly `size` bytes, the filler taken from
/// a pool of 1024 seeded bodies computed once, before warmup. Building an event is a prefix, a slice and a suffix.
sealed class PayloadFactory
{
    public const int PoolSize = 1024;
    readonly FillerPool _data;
    readonly FillerPool _metadata;

    public PayloadFactory(int dataSize, int metadataSize, ulong seed)
    {
        _data = new FillerPool(dataSize, seed);
        _metadata = new FillerPool(metadataSize, unchecked(seed + 0x9E3779B97F4A7C15UL));
    }

    public byte[] Data(long index) => _data.Payload(index);
    public byte[] Metadata(long index) => _metadata.Payload(index);

    sealed class FillerPool
    {
        static readonly byte[] Alphabet = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"u8.ToArray();
        static readonly byte[] Suffix = "\"}"u8.ToArray();
        readonly int _size;
        readonly int _width;
        /// Entry j occupies `_bytes[j * _width .. (j + 1) * _width]`.
        readonly byte[] _bytes;

        public FillerPool(int size, ulong seed)
        {
            // The filler of a one-digit index, the longest any index gets: size - len("{\"i\":0,\"p\":\"") - len("\"}").
            int width = size - Prefix(0).Length - Suffix.Length;
            if (width < 0) throw new UsageException($"payload size {size} is too small");
            var bytes = new byte[width * PoolSize];
            unchecked
            {
                for (int j = 0; j < PoolSize; j++)
                {
                    ulong state = seed ^ ((ulong)j * 0xBF58476D1CE4E5B9UL);
                    for (int b = 0; b < width; b++)
                    {
                        state += 0x9E3779B97F4A7C15UL;
                        ulong z = state;
                        z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9UL;
                        z = (z ^ (z >> 27)) * 0x94D049BB133111EBUL;
                        z ^= z >> 31;
                        bytes[j * width + b] = Alphabet[(int)(z % (ulong)Alphabet.Length)];
                    }
                }
            }
            _size = size;
            _width = width;
            _bytes = bytes;
        }

        static byte[] Prefix(long index) => Encoding.ASCII.GetBytes($"{{\"i\":{index},\"p\":\"");

        public byte[] Payload(long index)
        {
            var prefix = Prefix(index);
            int fillerCount = _size - prefix.Length - Suffix.Length;
            if (fillerCount < 0) throw new InvalidOperationException($"payload size {_size} is too small for index {index}");
            int entry = (int)(((index % PoolSize) + PoolSize) % PoolSize);
            var payload = new byte[_size];
            prefix.CopyTo(payload, 0);
            Buffer.BlockCopy(_bytes, entry * _width, payload, prefix.Length, fillerCount);
            Suffix.CopyTo(payload, prefix.Length + fillerCount);
            return payload;
        }
    }
}

/// `histogram.json` (HistogramFile.swift): `[lowestEquivalentValue, count]` per non-empty bucket, ascending.
static class HistogramFile
{
    public static object From(LongHistogram histogram)
    {
        var buckets = new List<ulong[]>();
        foreach (var v in histogram.RecordedValues())
            buckets.Add([(ulong)histogram.LowestEquivalentValue(v.ValueIteratedTo), (ulong)v.CountAddedInThisIterationStep]);
        return new { unit = "us", buckets };
    }
}

/// Resource usage of the current process, from the sources the Swift driver uses (ProcessUsage.swift): CPU seconds
/// (user, system) since process start from `getrusage(RUSAGE_SELF)`, and the process-lifetime peak resident set size
/// in bytes. On Linux the peak is `VmHWM` of /proc/self/status, the value `Process.PeakWorkingSet64` reads, not
/// `ru_maxrss`: the kernel folds the pre-exec address space's high-water mark into `ru_maxrss`, so a driver spawned
/// by the orchestrator would report at least the orchestrator's peak. `ru_maxrss` (bytes on macOS) is the fallback.
static class ProcessUsage
{
    [DllImport("libc", SetLastError = true)]
    static extern int getrusage(int who, [Out] long[] usage);

    public static (double User, double System, ulong MaxRss) Current()
    {
        // struct rusage on 64-bit Linux and macOS: two struct timeval (16 bytes each), then 14 longs (ru_maxrss
        // first). tv_usec is a long on Linux and a 32-bit int padded to 8 bytes on macOS; both fit the low 32 bits.
        var usage = new long[18];
        if (getrusage(0 /* RUSAGE_SELF */, usage) != 0)
            throw new InvalidOperationException($"getrusage failed: errno {Marshal.GetLastPInvokeError()}");
        static double Seconds(long sec, long usec) => sec + (int)(usec & 0xFFFF_FFFF) / 1_000_000.0;
        ulong raw = (ulong)Math.Max(usage[4], 0);
        ulong rss = OperatingSystem.IsLinux() ? PeakResidentFromProcStatus() ?? raw * 1024 : raw;
        return (Seconds(usage[0], usage[1]), Seconds(usage[2], usage[3]), rss);
    }

    /// `VmHWM` of /proc/self/status (`VmHWM:   1234 kB`) in bytes, or null when it cannot be read.
    static ulong? PeakResidentFromProcStatus()
    {
        try
        {
            foreach (var line in File.ReadLines("/proc/self/status"))
            {
                if (!line.StartsWith("VmHWM:", StringComparison.Ordinal)) continue;
                var fields = line["VmHWM:".Length..].Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries);
                return fields.Length >= 2 && fields[1] == "kB" && ulong.TryParse(fields[0], out var kib) ? kib * 1024 : null;
            }
        }
        catch (IOException) { }
        catch (UnauthorizedAccessException) { }
        return null;
    }
}
