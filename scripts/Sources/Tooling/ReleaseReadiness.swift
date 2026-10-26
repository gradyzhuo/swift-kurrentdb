import Foundation

/// Check that the documentation is ready for release X.Y.Z.
///
/// The release tag locks the DocC catalog and the README into `/X.Y/` and the site root for good,
/// and the landing page must flip to the new version in the same release, so this checks the
/// mechanical rows of the release checklist and prints one line per check:
///
///     ok       README.md: from: "2.7.0"
///     missing  docs/index.html: <option value="v2.7"> is the first option and marked (latest)
///
/// What it cannot check is whether each What's new bullet is also documented in the article that
/// covers the behaviour; that stays a review step.
///
/// Exit status: 0 when nothing is missing, 1 otherwise, with a GitHub `::error::` annotation per
/// missing row. CI runs it on the Prepare PR (`[UPDATE] prepare X.Y.Z: …`) and on the release tag.
public enum ReleaseReadiness {
    public static let usage = "usage: check-release-readiness X.Y.Z [--root DIR]"

    public static let readme = "README.md"
    public static let gettingStarted = "Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md"
    public static let whatsNew = "Sources/KurrentDB/KurrentDB.docc/Documentation.md"
    public static let landingPage = "docs/index.html"

    public struct Check: Equatable, Sendable {
        public var passed: Bool
        public var description: String
    }

    /// Every check for `version`, in checklist order.
    public static func checks(root: URL, version: ReleaseVersion) -> [Check] {
        let series = version.series
        var results: [Check] = []
        func check(_ passed: Bool, _ file: String, _ what: String) {
            results.append(Check(passed: passed, description: "\(file): \(what)"))
        }
        func read(_ relative: String) -> String {
            Text.read(root.appendingPathComponent(relative))
        }

        let pin = "from: \"\(version)\""
        check(read(readme).contains(pin), readme, pin)
        check(read(gettingStarted).contains(pin), gettingStarted, pin)

        let catalog = read(whatsNew)
        let section = catalog.range(of: "## What's new").map { String(catalog[$0.upperBound...]) } ?? ""
        let lines = Text.lines(of: section)
        let headings = lines.compactMap(headingText)
        check(headings.first.map(firstWord) == series, whatsNew, "first heading under What's new is ### \(series)")
        if version.patch > 0 {
            let entry = entryLines(lines, series: series)
            check(entry.contains { isBullet($0, endingWith: "(\(version))") }, whatsNew, "a bullet under ### \(series) ends with (\(version))")
        }

        let page = Text.unescapingHTML(read(landingPage))
        check(page.contains(pin), landingPage, pin)

        let option = firstOption(after: "id=\"release-select\"", in: page)
        check(
            option.map { $0.contains("value=\"v\(series)\"") && $0.contains("(latest)") } ?? false,
            landingPage,
            "<option value=\"v\(series)\"> is the first option and marked (latest)"
        )

        let article = element(opening: "<article class=\"release\" id=\"v\(series)\">", closing: "</article>", in: page)
        check(article != nil, landingPage, "<article class=\"release\" id=\"v\(series)\">")
        let latest = elements(opening: "<div class=\"whats-new-tag\">", closing: "</div>", in: page).filter { $0.contains("Latest ·") }
        check(
            latest.count == 1 && latest[0].contains("Latest · v\(version)") && article.map { $0.contains(latest[0]) } == true,
            landingPage,
            "exactly one \"Latest · vX.Y.Z\" tag, on the v\(series) article, saying Latest · v\(version)"
        )
        check(article?.contains("releases/tag/\(version)") == true, landingPage, "the v\(series) article links to releases/tag/\(version)")
        return results
    }

    public static func run(_ arguments: [String]) throws(ToolError) -> String {
        let arguments = try Arguments(arguments, usage: usage, options: ["root"])
        let text = try arguments.positional(count: 1)[0]
        guard let version = ReleaseVersion(text) else {
            throw ToolError(status: 2, message: "version must be X.Y.Z, got '\(text)'\n\(usage)")
        }
        let root = URL(fileURLWithPath: arguments.value("root", default: "."))

        var report = ["release \(version)"]
        var missing = 0
        for check in checks(root: root, version: version) {
            report.append("  \(check.passed ? "ok     " : "missing")  \(check.description)")
            if !check.passed {
                missing += 1
                let file = check.description.split(separator: ":", maxSplits: 1)[0]
                report.append("::error file=\(file)::release \(version): missing \(check.description)")
            }
        }
        let output = report.joined(separator: "\n")
        if missing > 0 {
            throw ToolError(status: 1, message: "\(missing) missing", output: output)
        }
        return output
    }

    // MARK: Markdown

    /// The text after `### ` of a level-3 heading line, or nil.
    private static func headingText(_ line: String) -> String? {
        line.hasPrefix("### ") ? String(line.dropFirst(4)) : nil
    }

    private static func firstWord(_ text: String) -> String {
        String(text.prefix { !$0.isWhitespace })
    }

    /// The lines under the first `### <series>` heading (exactly that, or followed by a space), up to the next level-3 heading.
    private static func entryLines(_ lines: [String], series: String) -> [String] {
        guard let start = lines.firstIndex(where: { line in
            headingText(line).map { $0 == series || $0.hasPrefix(series + " ") } ?? false
        }) else { return [] }
        let body = lines[(start + 1)...]
        return Array(body.prefix { headingText($0) == nil })
    }

    /// A `- ` or `* ` bullet whose text ends with `suffix`, allowing a trailing full stop.
    private static func isBullet(_ line: String, endingWith suffix: String) -> Bool {
        var text = line.trimmingCharacters(in: .whitespaces)
        guard text.hasPrefix("- ") || text.hasPrefix("* ") else { return false }
        if text.hasSuffix(".") { text.removeLast() }
        return text.hasSuffix(suffix)
    }

    // MARK: HTML

    /// The first `<option …>` tag after `marker`.
    private static func firstOption(after marker: String, in page: String) -> String? {
        guard let markerRange = page.range(of: marker) else { return nil }
        let rest = page[markerRange.upperBound...]
        guard let start = rest.range(of: "<option "), let end = rest[start.upperBound...].firstIndex(of: ">") else { return nil }
        return String(rest[start.lowerBound...end])
    }

    /// The content between the first `opening` and the next `closing`.
    private static func element(opening: String, closing: String, in page: String) -> String? {
        elements(opening: opening, closing: closing, in: page).first
    }

    private static func elements(opening: String, closing: String, in page: String) -> [String] {
        var found: [String] = []
        var rest = Substring(page)
        while let start = rest.range(of: opening), let end = rest[start.upperBound...].range(of: closing) {
            found.append(String(rest[start.upperBound..<end.lowerBound]))
            rest = rest[end.upperBound...]
        }
        return found
    }
}
