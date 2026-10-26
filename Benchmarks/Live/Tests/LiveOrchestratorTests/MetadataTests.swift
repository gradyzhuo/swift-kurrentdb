import Foundation
@testable import LiveBenchCore
@testable import LiveOrchestrator
import Testing

/// Private IPv4 addresses (RFC 1918), as the plan's check writes them.
private let privateAddress = #"\b(10|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+"#
/// The same with all four octets: the plan's pattern also matches versions such as `10.0.5`, which NuGet lock files
/// are full of.
private let privateAddressFourOctets = #"\b(10\.\d+|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d+\.\d+"#

@Suite("Run metadata")
struct MetadataTests {
    @Test func metadataHasNoHostIdentity() throws {
        let json = try String(data: JSONEncoder().encode(RunMetadata.collect(environment: ["HOSTNAME": "secret-box", "USER": "alice"])), encoding: .utf8)!
        #expect(!json.contains("secret-box")); #expect(!json.contains("alice"))
        #expect(json.range(of: privateAddress, options: .regularExpression) == nil)
    }

    @Test func collectReadsRunnerAndCpuFromItsSources() {
        let cpuinfo = "processor\t: 0\nvendor_id\t: AuthenticAMD\nmodel name\t: AMD EPYC 7763 64-Core Processor\n"
        let metadata = RunMetadata.collect(
            environment: [
                "GITHUB_SHA": "feedface", "ImageOS": "ubuntu24", "ImageVersion": "20261020.1",
                "HOSTNAME": "secret-box", "USER": "alice",
            ],
            readFile: { $0 == "/proc/cpuinfo" ? cpuinfo : nil },
            command: { arguments in
                switch arguments.first {
                case "swift": "Swift version 6.4 (swift-6.4-RELEASE)\nTarget: x86_64-unknown-linux-gnu\n"
                // A toolchain that prints the user's home or the host's address is redacted, not recorded.
                case "dotnet": "8.0.404 [/home/alice/.dotnet/sdk] on secret-box 192.168.1.20"
                default: nil
                }
            },
            now: Date(timeIntervalSince1970: 1_793_059_200)  // 2026-10-27T00:00:00Z
        )
        #expect(metadata.harnessCommit == "feedface")
        #expect(metadata.sdkCommit == "feedface")
        #expect(metadata.runnerImageVersion == "ubuntu24 20261020.1")
        #expect(metadata.cpuModel == "AMD EPYC 7763 64-Core Processor")
        #expect(metadata.swiftToolchain == "Swift version 6.4 (swift-6.4-RELEASE)")
        #expect(metadata.runDate == "2026-10-27")
        let dotnet = metadata.dotnetRuntime ?? ""
        #expect(!dotnet.contains("alice") && !dotnet.contains("secret-box") && !dotnet.contains("192.168"))
        #expect(dotnet.hasPrefix("8.0.404"))
    }

    @Test func identityRedactionTouchesValuesNotKeys() throws {
        // On GitHub runners USER=runner: the field `runnerImageVersion` must survive.
        let runner = RunMetadata.collect(
            environment: ["USER": "runner", "ImageOS": "ubuntu24", "ImageVersion": "20261020.1"],
            readFile: { _ in nil }, command: { _ in nil }
        )
        #expect(runner.runnerImageVersion == "ubuntu24 20261020.1")

        // A short identity that is part of field names ("runDate", "corpusReducedTo", ...) still decodes and leaks
        // nowhere in the values.
        let short = RunMetadata.collect(
            environment: ["HOSTNAME": "ate", "GITHUB_SHA": "late-commit", "ImageOS": "private-gate"],
            readFile: { $0 == "/proc/cpuinfo" ? "model name\t: Gate CPU\n" : nil }, command: { _ in nil }
        )
        #expect(short.runDate != nil)
        #expect(short.harnessCommit == "l<redacted>-commit")
        #expect(short.cpuModel == "G<redacted> CPU")
        let values = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(short)) as? [String: Any])
        for case let value as String in values.values { #expect(!value.contains("ate"), "\(value)") }
    }

    @Test func redactionKeepsJsonValidAroundBackslashes() throws {
        var record = TrialRecord(round: 0, rate: 1, driver: "swift")
        record.error = #"path C:\/Users/alice/x and "quoted" \home"#
        record.headroom = HeadroomSample(coreBusy: [.nan], diskAwaitMillis: .infinity, diskQueueDepth: 0, projectionBufferedStart: 0, projectionBufferedEnd: 0, eventsWritten: 0)
        let scrubbed = try HostRedaction.scrubbing(record)
        // The decoded string is scrubbed, not the JSON text, so no stray `\~` escape can appear.
        #expect(scrubbed.error == #"path C:~/x and "quoted" \home"#)
        #expect(scrubbed.headroom?.coreBusy.first?.isNaN == true)
    }

    @Test func driverReportedValuesWinOverCollected() {
        var fromDrivers = RunMetadata()
        fromDrivers.swiftToolchain = "swift 6.2"
        var collected = RunMetadata()
        collected.swiftToolchain = "Swift version 6.4"
        collected.cpuModel = "cpu"
        let merged = fromDrivers.filling(from: collected)
        #expect(merged.swiftToolchain == "swift 6.2")
        #expect(merged.cpuModel == "cpu")
    }

    @Test func redactionRemovesHomesAndPrivateAddresses() {
        let text = #"open /Users/alice/x and \/home\/bob\/y via 10.1.2.3, 172.20.0.5:2113, 192.168.0.9; keep 127.0.0.1 and 10.0.1"#
        let scrubbed = HostRedaction.scrub(text)
        #expect(scrubbed == #"open ~/x and ~\/y via <private-ip>, <private-ip>:2113, <private-ip>; keep 127.0.0.1 and 10.0.1"#)
    }
}

@Suite("Results bundle")
struct MergeTests {
    @Test func mergeWritesOneFolderPerCellWithMetadataAndReport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("merge-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let input = root.appendingPathComponent("in")
        for result in [CellResult.fixturePersistent, .fixtureWithLosses] {
            // As actions/download-artifact lays them out: one directory per cell artifact.
            let cellDirectory = input.appendingPathComponent("cell-\(result.cell.id)")
            let trial = cellDirectory.appendingPathComponent("trials/r0-250-swift")
            try FileManager.default.createDirectory(at: trial, withIntermediateDirectories: true)
            try writeCellResult(result, to: cellDirectory.appendingPathComponent("cell-result.json"))
            try Data("connect 192.168.1.20 from /Users/alice/work\n".utf8).write(to: trial.appendingPathComponent("stderr.log"))
        }

        let bundle = try Merge.bundle(from: input, into: root.appendingPathComponent("results"))

        #expect(bundle.lastPathComponent == "2026-10-27-26.2.3")
        let names = try FileManager.default.contentsOfDirectory(atPath: bundle.path).sorted()
        #expect(names.contains("metadata.json"))
        #expect(names.contains("report.html"))
        #expect(names.contains("persistent-fixture"))
        #expect(names.contains("append-latency-losses"))
        let copied = bundle.appendingPathComponent("persistent-fixture/trials/r0-250-swift/stderr.log")
        #expect(try String(contentsOf: copied, encoding: .utf8) == "connect <private-ip> from ~/work\n")
        let reloaded = try JSONDecoder().decode(CellResult.self, from: Data(contentsOf: bundle.appendingPathComponent("persistent-fixture/cell-result.json")))
        #expect(reloaded.trials.count == CellResult.fixturePersistent.trials.count)

        // Nothing in the bundle names a home directory or a private address.
        let files = FileManager.default.enumerator(at: bundle, includingPropertiesForKeys: nil)!.compactMap { $0 as? URL }
        for file in files where !file.hasDirectoryPath {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            #expect(!text.contains("/Users/alice"), "\(file.lastPathComponent)")
            #expect(!text.contains("/home/bob"), "\(file.lastPathComponent)")
            #expect(text.range(of: privateAddressFourOctets, options: .regularExpression) == nil, "\(file.lastPathComponent)")
        }
    }

    @Test func mergeWithoutCellResultsFails() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("merge-empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(throws: (any Error).self) { try Merge.bundle(from: root, into: root.appendingPathComponent("out")) }
    }
}
