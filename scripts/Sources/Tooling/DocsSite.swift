import Foundation

/// Assemble the GitHub Pages site: the landing page plus one DocC build per version.
///
///     /<base>/                                     landing page (docs/)
///     /<base>/documentation/kurrentdb/             latest release
///     /<base>/<label>/documentation/kurrentdb/     every release (including the latest) and main
///     /<base>/doc-versions.json                    the version menu's entries, newest first
///
/// `--inputs` holds one directory per label (`2.5`, ..., `main`), each with the version's
/// `KurrentDB.symbols.json` and its `KurrentDB.docc` catalog. `--releases` is the output of
/// `doc-versions`; `main` is added after the releases.
///
/// Every generated page loads `/<base>/doc-versions.js` (from docs/), which draws the menu.
public enum DocsSite {
    public static let usage = "usage: build-docs-site --inputs DIR --releases JSON --output DIR [--landing DIR] [--base PATH] [--docc \"xcrun docc\"]"

    public struct Version: Decodable, Equatable, Sendable {
        public var label: String
        public var ref: String

        public init(label: String, ref: String) {
            self.label = label
            self.ref = ref
        }
    }

    public static func run(_ arguments: [String]) throws(ToolError) -> String {
        let arguments = try Arguments(arguments, usage: usage, options: ["inputs", "releases", "output", "landing", "base", "docc"])
        _ = try arguments.positional(count: 0)
        guard let inputs = arguments.value("inputs"), let releasesJSON = arguments.value("releases"), let output = arguments.value("output") else {
            throw ToolError(status: 2, message: "--inputs, --releases and --output are required\n\(usage)")
        }
        let releases: [Version]
        do {
            releases = try JSONDecoder().decode([Version].self, from: Data(releasesJSON.utf8))
        } catch {
            throw ToolError(status: 2, message: "--releases must be the JSON array doc-versions prints: \(error)")
        }
        let inputsURL = URL(fileURLWithPath: inputs)
        let outputURL = URL(fileURLWithPath: output)
        let landing = URL(fileURLWithPath: arguments.value("landing", default: "docs"))
        let base = arguments.value("base", default: "swift-kurrentdb")
        let docc = arguments.value("docc", default: "docc").split(whereSeparator: \.isWhitespace).map(String.init)
        let versions = releases + [Version(label: "main", ref: "main")]

        guard !FileManager.default.fileExists(atPath: outputURL.path) else {
            throw ToolError(message: "error: \(output) already exists")
        }
        try files { try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true) }

        for version in versions {
            try convert(docc, source: inputsURL.appendingPathComponent(version.label), hostingBasePath: "\(base)/\(version.label)", output: outputURL.appendingPathComponent(version.label))
        }

        // The latest release is also published at the root, so the plain
        // /documentation/kurrentdb/ links always show what users install.
        if let latest = releases.first {
            let scratch = try temporaryDirectory()
            let docs = scratch.appendingPathComponent("docc")
            try convert(docc, source: inputsURL.appendingPathComponent(latest.label), hostingBasePath: base, output: docs)
            try files { try FileManager.default.removeItem(at: docs.appendingPathComponent("index.html")) }  // the landing page owns /index.html
            try merge(docs, into: outputURL, origin: "DocC (latest release)")
            try files { try FileManager.default.removeItem(at: scratch) }
        }

        let menuScript = "<script defer src=\"/\(base)/doc-versions.js\"></script>"
        for page in Files.files(under: outputURL, suffix: "index.html") where page.lastPathComponent == "index.html" {
            let html = Text.read(page)
            guard let head = html.range(of: "</head>") else { continue }
            try files { try html.replacingCharacters(in: head, with: menuScript + "</head>").write(to: page, atomically: true, encoding: .utf8) }
        }

        let entries = versions.enumerated().map { index, version in
            "  {\n    \"title\": \"\(version.ref)\",\n    \"path\": \"\(version.label)\",\n    \"latest\": \(index == 0 && !releases.isEmpty)\n  }"
        }
        try files { try ("[\n" + entries.joined(separator: ",\n") + "\n]\n").write(to: outputURL.appendingPathComponent("doc-versions.json"), atomically: true, encoding: .utf8) }

        try merge(landing, into: outputURL, origin: landing.relativePath)
        return ""
    }

    /// One `docc convert` of `source`'s catalog with its symbol graph into `output`.
    static func convert(_ docc: [String], source: URL, hostingBasePath: String, output: URL) throws(ToolError) {
        let symbolGraphs = try temporaryDirectory()
        try files { try FileManager.default.copyItem(at: source.appendingPathComponent("KurrentDB.symbols.json"), to: symbolGraphs.appendingPathComponent("KurrentDB.symbols.json")) }
        try Shell.run(docc + [
            "convert", source.appendingPathComponent("KurrentDB.docc").path,
            "--additional-symbol-graph-dir", symbolGraphs.path,
            "--fallback-display-name", "KurrentDB",
            "--fallback-bundle-identifier", "KurrentDB",
            "--transform-for-static-hosting",
            "--hosting-base-path", hostingBasePath,
            "--output-path", output.path,
        ], capturingOutput: false)
        try files { try FileManager.default.removeItem(at: symbolGraphs) }
    }

    /// Copies the entries of `source` into `destination`; a name both sides use is an error, not an overwrite.
    static func merge(_ source: URL, into destination: URL, origin: String) throws(ToolError) {
        let entries = try files { try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil, options: []) }
        for entry in entries {
            let target = destination.appendingPathComponent(entry.lastPathComponent)
            guard !FileManager.default.fileExists(atPath: target.path) else {
                throw ToolError(message: "error: \(origin)/\(entry.lastPathComponent) collides with an existing site path")
            }
            try files { try FileManager.default.copyItem(at: entry, to: target) }
        }
    }

    private static func temporaryDirectory() throws(ToolError) -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("build-docs-site-\(UUID().uuidString)")
        try files { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        return url
    }

    /// Turns a file system error into a `ToolError`.
    private static func files<T>(_ body: () throws -> T) throws(ToolError) -> T {
        do {
            return try body()
        } catch {
            throw ToolError(message: "error: \(error)")
        }
    }
}
