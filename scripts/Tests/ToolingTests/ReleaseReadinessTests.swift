import Testing
@testable import Tooling

@Suite struct ReleaseReadinessTests {
    static func landingPage(latest: String, previous: String, latestSeries: String, previousSeries: String) -> String {
        """
        <pre><code>.package(url: "x", from: "\(latest)")</code></pre>
        <select id="release-select">
          <option value="v\(latestSeries)" data-en="\(latestSeries) (latest)">\(latestSeries) (latest)</option>
          <option value="v\(previousSeries)" data-en="\(previousSeries)">\(previousSeries)</option>
        </select>
        <article class="release" id="v\(latestSeries)">
          <div class="whats-new-tag"><span lang="en">Latest &middot; v\(latest)</span></div>
          <a href="https://github.com/x/releases/tag/\(latest)">notes</a>
        </article>
        <article class="release" id="v\(previousSeries)">
          <div class="whats-new-tag">v\(previous)</div>
          <a href="https://github.com/x/releases/tag/\(previous)">notes</a>
        </article>

        """
    }

    /// A tree with every surface updated for `version`.
    static func readyTree(_ version: String) -> TemporaryDirectory {
        let series = ReleaseVersion(version)!.series
        let tree = TemporaryDirectory()
        tree.write(ReleaseReadiness.readme, ".package(url: \"x\", from: \"\(version)\")\n")
        tree.write(ReleaseReadiness.gettingStarted, ".package(url: \"x\", from: \"\(version)\")\n")
        tree.write(ReleaseReadiness.whatsNew, "# KurrentDB\n\n## What's new\n\n### \(series)\n\n- **Thing.** Done (\(version)).\n\n### 2.6\n\n- Old.\n")
        tree.write(ReleaseReadiness.landingPage, landingPage(latest: version, previous: "2.6.0", latestSeries: series, previousSeries: "2.6"))
        return tree
    }

    static func failures(_ tree: TemporaryDirectory, _ version: String) -> [String] {
        ReleaseReadiness.checks(root: tree.url, version: ReleaseVersion(version)!).filter { !$0.passed }.map(\.description)
    }

    @Test func readyMinorPassesEveryCheck() {
        #expect(Self.failures(Self.readyTree("2.7.0"), "2.7.0") == [])
    }

    @Test func readyPatchPassesWithItsBullet() {
        #expect(Self.failures(Self.readyTree("2.7.1"), "2.7.1") == [])
    }

    @Test func patchNeedsABulletNamingIt() {
        let tree = Self.readyTree("2.7.1")
        tree.write(ReleaseReadiness.whatsNew, "## What's new\n\n### 2.7\n\n- **Thing.** Done.\n")
        #expect(Self.failures(tree, "2.7.1") == ["\(ReleaseReadiness.whatsNew): a bullet under ### 2.7 ends with (2.7.1)"])
    }

    @Test func patchBulletMustEndWithTheVersion() {
        let tree = Self.readyTree("2.7.1")
        let expected = ["\(ReleaseReadiness.whatsNew): a bullet under ### 2.7 ends with (2.7.1)"]
        // A mention in prose is not an entry for the patch.
        tree.write(ReleaseReadiness.whatsNew, "## What's new\n\n### 2.7\n\nAlso fixed in (2.7.1).\n\n- **Thing.** Done.\n")
        #expect(Self.failures(tree, "2.7.1") == expected)
        // Neither is a bullet that names the version before its text.
        tree.write(ReleaseReadiness.whatsNew, "## What's new\n\n### 2.7\n\n- **Thing (2.7.1).** Done.\n")
        #expect(Self.failures(tree, "2.7.1") == expected)
    }

    @Test func untouchedTreeReportsEverySurface() {
        let missing = Self.failures(Self.readyTree("2.6.0"), "2.7.0")
        let files = Set(missing.map { String($0.split(separator: ":", maxSplits: 1)[0]) })
        #expect(files == [ReleaseReadiness.readme, ReleaseReadiness.gettingStarted, ReleaseReadiness.whatsNew, ReleaseReadiness.landingPage])
        #expect(missing.count == 8)
    }

    @Test func landingPageLatestMustMoveToTheNewArticle() {
        let tree = Self.readyTree("2.7.0")
        // The new article exists, but the previous one still carries the Latest tag.
        let page = tree.read(ReleaseReadiness.landingPage)
            .replacingOccurrences(of: "Latest &middot; v2.7.0", with: "v2.7.0")
            .replacingOccurrences(of: "tag\">v2.6.0", with: "tag\">Latest · v2.6.0")
        tree.write(ReleaseReadiness.landingPage, page)
        #expect(Self.failures(tree, "2.7.0") == [
            "\(ReleaseReadiness.landingPage): exactly one \"Latest · vX.Y.Z\" tag, on the v2.7 article, saying Latest · v2.7.0",
        ])
    }

    @Test func landingPageNewOptionMustComeFirst() {
        let tree = Self.readyTree("2.7.0")
        var lines = Text.lines(of: tree.read(ReleaseReadiness.landingPage))
        let first = lines.firstIndex(of: "  <option value=\"v2.7\" data-en=\"2.7 (latest)\">2.7 (latest)</option>")!
        lines.swapAt(first, first + 1)
        tree.write(ReleaseReadiness.landingPage, lines.joined(separator: "\n") + "\n")
        #expect(Self.failures(tree, "2.7.0") == [
            "\(ReleaseReadiness.landingPage): <option value=\"v2.7\"> is the first option and marked (latest)",
        ])
    }

    @Test func whatsNewHeadingMustBeFirst() {
        let tree = Self.readyTree("2.7.0")
        tree.write(ReleaseReadiness.whatsNew, "## What's new\n\n### 2.6\n\n- Old.\n\n### 2.7\n\n- New.\n")
        #expect(Self.failures(tree, "2.7.0") == ["\(ReleaseReadiness.whatsNew): first heading under What's new is ### 2.7"])
    }

    @Test func readyTreePasses() throws {
        let tree = Self.readyTree("2.7.0")
        let report = try ReleaseReadiness.run(["--root", tree.url.path, "2.7.0"])
        #expect(report.hasPrefix("release 2.7.0\n  ok       README.md: from: \"2.7.0\"\n"))
        #expect(!report.contains("missing"))
    }

    @Test func missingRowsFailWithErrorAnnotations() {
        let tree = Self.readyTree("2.6.0")
        let error = failure { try ReleaseReadiness.run(["--root", tree.url.path, "2.7.0"]) }
        #expect(error?.status == 1)
        #expect(error?.message == "8 missing")
        #expect(error?.output.contains("::error file=README.md::release 2.7.0: missing README.md: from: \"2.7.0\"") == true)
    }

    @Test func versionMustBeAReleaseNumber() {
        for version in ["v2.7.0", "2.7", "pre/2.7.0"] {
            #expect(failure { try ReleaseReadiness.run([version]) }?.status == 2, "\(version)")
        }
        #expect(failure { try ReleaseReadiness.run([]) }?.status == 2)
    }
}
