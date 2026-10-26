import Testing
@testable import Tooling

@Suite struct DocVersionsTests {
    @Test func latestPatchOfEveryMinorNewestFirst() {
        let tags = ["1.11.2", "1.12.0", "2.0.0-beta.5", "2.0.0", "2.4.3", "2.4.1", "2.10.0", "archive/main-before-rewrite", "2.4.10"]
        let releases = DocVersions.releases(tags: tags, minimum: (1, 12)).map(\.description)
        #expect(releases == ["2.10.0", "2.4.10", "2.0.0", "1.12.0"])
    }

    @Test func minimumIsInclusive() {
        let releases = DocVersions.releases(tags: ["2.4.0", "2.5.0", "2.6.0"], minimum: (2, 5)).map(\.description)
        #expect(releases == ["2.6.0", "2.5.0"])
    }

    @Test func printsReleasesAndTheMainEntryFromGitTags() throws {
        let repo = TemporaryDirectory()
        try Shell.run(["git", "init", "-q"], in: repo.url)
        try Shell.run(["git", "-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"], in: repo.url)
        try Shell.run(["git", "tag", "2.6.0"], in: repo.url)
        try Shell.run(["git", "tag", "2.6.1"], in: repo.url)
        let commit = try Git.commit(of: "2.6.1", in: repo.url)

        let releases = try DocVersions.run(["--root", repo.url.path])
        #expect(releases == "[{\"label\": \"2.6\", \"ref\": \"2.6.1\", \"commit\": \"\(commit)\"}]")
        let matrix = try DocVersions.run(["--root", repo.url.path, "--main", "abc"])
        #expect(matrix.hasSuffix(", {\"label\": \"main\", \"ref\": \"abc\", \"commit\": \"\"}]"))
    }

    @Test func minimumMustBeMajorMinor() {
        #expect(failure { try DocVersions.run(["--minimum", "1"]) }?.status == 2)
    }
}
