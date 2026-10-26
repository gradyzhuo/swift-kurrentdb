import Foundation

/// List the releases whose documentation is published on GitHub Pages.
///
/// Prints a JSON array, newest first, with one entry per minor release: the latest patch tag
/// of every `major.minor` from the minimum version on. Pre-release tags (`2.0.0-beta.5`) are
/// ignored, and a new patch replaces the previous one of its minor.
///
///     [{"label": "2.5", "ref": "2.5.0", "commit": "9b8603f4..."}, ...]
///
/// `label` is the URL segment (`/swift-kurrentdb/2.5/documentation/kurrentdb/`), so a minor
/// keeps its URL across patches; `ref` is the tag the documentation is built from and `commit`
/// the commit it points at (the CI cache key, so a moved tag is rebuilt).
public enum DocVersions {
    public static let usage = """
        usage: doc-versions [--minimum MAJOR.MINOR] [--main REF] [--root DIR]   (reads the tags with `git tag`)
          --main REF   append {"label": "main", "ref": REF, "commit": ""} for the build matrix
        """

    /// The latest patch of every minor from `minimum` on, newest first.
    public static func releases(tags: [String], minimum: (major: Int, minor: Int)) -> [ReleaseVersion] {
        var latest: [String: ReleaseVersion] = [:]
        for tag in tags {
            guard let version = ReleaseVersion(tag), (version.major, version.minor) >= minimum else { continue }
            if let known = latest[version.series], known > version { continue }
            latest[version.series] = version
        }
        return latest.values.sorted(by: >)
    }

    public static func run(_ arguments: [String]) throws(ToolError) -> String {
        let arguments = try Arguments(arguments, usage: usage, options: ["minimum", "main", "root"])
        _ = try arguments.positional(count: 0)
        let minimumText = arguments.value("minimum", default: "1.12")
        let parts = minimumText.split(separator: ".").map { Int($0) }
        guard parts.count == 2, let major = parts[0], let minor = parts[1] else {
            throw ToolError(status: 2, message: "--minimum must be MAJOR.MINOR, got '\(minimumText)'\n\(usage)")
        }
        let root = URL(fileURLWithPath: arguments.value("root", default: "."))

        var entries = try releases(tags: Git.tags(in: root), minimum: (major, minor)).map { (version) throws(ToolError) -> String in
            try entry(label: version.series, ref: version.description, commit: Git.commit(of: version.description, in: root))
        }
        if let main = arguments.value("main") {
            entries.append(entry(label: "main", ref: main, commit: ""))
        }
        return "[" + entries.joined(separator: ", ") + "]"
    }

    private static func entry(label: String, ref: String, commit: String) -> String {
        "{\"label\": \"\(label)\", \"ref\": \"\(ref)\", \"commit\": \"\(commit)\"}"
    }
}
