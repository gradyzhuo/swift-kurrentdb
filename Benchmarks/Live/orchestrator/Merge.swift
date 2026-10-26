import Foundation
import LiveBenchCore

/// Assembles the results bundle a maintainer commits under `Benchmarks/Live/results/`:
///
/// ```
/// <results>/<YYYY-MM-DD>-<server version>/
///   <cell id>/cell-result.json, trials/…   (each cell's raw files)
///   metadata.json                          (every cell's RunMetadata, by cell id)
///   dependencies/Package.resolved, packages.lock.json
///   report.html
/// ```
///
/// The date is the earliest `runDate` and the server version the tag of the most common `serverImage` among the
/// cells. Every text file is copied through `HostRedaction.scrub` (home directories become `~`, private addresses
/// `<private-ip>`): driver logs and errors can carry local temporary paths.
enum Merge {
    struct NoCellResults: Error, CustomStringConvertible {
        var directory: String
        var description: String { "no cell-result.json under \(directory)" }
    }

    struct DuplicateCell: Error, CustomStringConvertible {
        var id: String
        var description: String { "cell \(id) appears in more than one cell-result.json" }
    }

    /// `Benchmarks/Live`, found from this source file.
    static let harnessDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    /// Builds the bundle from every `cell-result.json` under `input` (at any depth, next to its `trials/`) inside
    /// `resultsDirectory` and returns its directory. An existing bundle of the same name is replaced.
    @discardableResult
    static func bundle(from input: URL, into resultsDirectory: URL, harness: URL = harnessDirectory) throws -> URL {
        let fileManager = FileManager.default
        let files = (fileManager.enumerator(at: input, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? [])
            .filter { $0.lastPathComponent == "cell-result.json" }
            .sorted { $0.path < $1.path }
        guard !files.isEmpty else { throw NoCellResults(directory: input.path) }

        var cells: [(result: CellResult, directory: URL)] = []
        for file in files {
            let raw = try JSONDecoder().decode(CellResult.self, from: Data(contentsOf: file))
            guard let result = HostRedaction.scrubbing(raw) else { throw CocoaError(.coderInvalidValue) }
            guard !cells.contains(where: { $0.result.cell.id == result.cell.id }) else { throw DuplicateCell(id: result.cell.id) }
            cells.append((result, file.deletingLastPathComponent()))
        }
        cells.sort { ($0.result.cell.tier == .headline ? 0 : 1, $0.result.cell.id) < ($1.result.cell.tier == .headline ? 0 : 1, $1.result.cell.id) }

        let bundle = resultsDirectory.appendingPathComponent(bundleName(cells.map(\.result.metadata)))
        if fileManager.fileExists(atPath: bundle.path) { try fileManager.removeItem(at: bundle) }
        try fileManager.createDirectory(at: bundle, withIntermediateDirectories: true)

        for (result, directory) in cells {
            let destination = bundle.appendingPathComponent(safeName(result.cell.id))
            try copyScrubbed(from: directory, to: destination, skipping: ["cell-result.json"])
            try writeCellResult(result, to: destination.appendingPathComponent("cell-result.json"))
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let metadata = Dictionary(uniqueKeysWithValues: cells.map { ($0.result.cell.id, $0.result.metadata) })
        try encoder.encode(["cells": metadata]).write(to: bundle.appendingPathComponent("metadata.json"))

        let dependencies = bundle.appendingPathComponent("dependencies")
        for source in ["Package.resolved", "drivers/dotnet/packages.lock.json"] {
            let file = harness.appendingPathComponent(source)
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            try fileManager.createDirectory(at: dependencies, withIntermediateDirectories: true)
            try Data(HostRedaction.scrub(text).utf8).write(to: dependencies.appendingPathComponent(file.lastPathComponent))
        }

        try Data(Report.render(cells.map(\.result)).utf8).write(to: bundle.appendingPathComponent("report.html"))
        return bundle
    }

    /// `<earliest run date>-<server version>`, e.g. `2026-10-27-26.2.3`.
    static func bundleName(_ metadata: [RunMetadata]) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        let date = metadata.compactMap(\.runDate).min() ?? formatter.string(from: Date())
        let versions = metadata.compactMap(\.serverImage).map { image -> String in
            let name = image.split(separator: "@").first.map(String.init) ?? image
            guard let colon = name.lastIndex(of: ":"), !name[name.index(after: colon)...].contains("/") else { return "unknown" }
            return String(name[name.index(after: colon)...])
        }
        let counts = Dictionary(versions.map { ($0, 1) }, uniquingKeysWith: +)
        let version = counts.max { ($0.value, $1.key) < ($1.value, $0.key) }?.key ?? "unknown"
        return safeName("\(date)-\(version)")
    }

    private static func safeName(_ name: String) -> String {
        String(name.map { $0.isLetter || $0.isNumber || "-._".contains($0) ? $0 : "_" })
    }

    /// Copies the tree under `source` into `destination`; UTF-8 files go through `HostRedaction.scrub`.
    private static func copyScrubbed(from source: URL, to destination: URL, skipping: Set<String>) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let base = source.standardizedFileURL.resolvingSymlinksInPath().path
        guard let enumerator = fileManager.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey]) else { return }
        for case let file as URL in enumerator {
            guard (try? file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = file.standardizedFileURL.resolvingSymlinksInPath().path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            if skipping.contains(relative) { continue }
            let target = destination.appendingPathComponent(relative)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Data(contentsOf: file)
            if let text = String(data: data, encoding: .utf8) {
                try Data(HostRedaction.scrub(text).utf8).write(to: target)
            } else {
                try data.write(to: target)
            }
        }
    }
}
