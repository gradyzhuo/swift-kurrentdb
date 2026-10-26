import Foundation
import Testing
@testable import Tooling

@Suite struct DocsSiteTests {
    /// A stand-in for `docc convert` that writes the two pages the site needs into `--output-path`.
    static func fakeDocc(in directory: TemporaryDirectory) -> String {
        directory.write("docc", """
        #!/bin/sh
        while [ $# -gt 0 ]; do
          case "$1" in
            --output-path) out="$2"; shift ;;
            --hosting-base-path) base="$2"; shift ;;
          esac
          shift
        done
        mkdir -p "$out/documentation/kurrentdb" "$out/css"
        printf '<html><head><title>%s</title></head></html>' "$base" > "$out/index.html"
        printf '<html><head></head><body>%s</body></html>' "$base" > "$out/documentation/kurrentdb/index.html"
        printf 'body{}' > "$out/css/site.css"
        """)
        let path = directory.url.appendingPathComponent("docc").path
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        return path
    }

    @Test func assemblesEveryVersionTheRootAndTheLandingPage() throws {
        let directory = TemporaryDirectory()
        let docc = Self.fakeDocc(in: directory)
        for label in ["2.6", "2.5", "main"] {
            directory.write("inputs/\(label)/KurrentDB.symbols.json", "{}")
            directory.write("inputs/\(label)/KurrentDB.docc/Documentation.md", "# KurrentDB")
        }
        directory.write("docs/index.html", "<html><head></head><body>landing</body></html>")
        directory.write("docs/doc-versions.js", "// menu")
        directory.write("docs/.nojekyll", "")
        let output = directory.url.appendingPathComponent("_site")

        let printed = try DocsSite.run([
            "--inputs", directory.url.appendingPathComponent("inputs").path,
            "--releases", "[{\"label\": \"2.6\", \"ref\": \"2.6.1\", \"commit\": \"a\"}, {\"label\": \"2.5\", \"ref\": \"2.5.0\", \"commit\": \"b\"}]",
            "--output", output.path,
            "--landing", directory.url.appendingPathComponent("docs").path,
            "--docc", docc,
        ])
        #expect(printed == "")

        let menu = "<script defer src=\"/swift-kurrentdb/doc-versions.js\"></script></head>"
        for label in ["2.6", "2.5", "main"] {
            let page = directory.read("_site/\(label)/documentation/kurrentdb/index.html")
            #expect(page.contains(menu) && page.contains("swift-kurrentdb/\(label)"), "\(label)")
        }
        // The latest release again at the root, under the landing page.
        #expect(directory.read("_site/documentation/kurrentdb/index.html").contains("<body>swift-kurrentdb</body>"))
        #expect(directory.read("_site/css/site.css") == "body{}")
        #expect(directory.read("_site/index.html") == "<html><head></head><body>landing</body></html>")
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent(".nojekyll").path))
        #expect(directory.read("_site/doc-versions.json") == """
        [
          {
            "title": "2.6.1",
            "path": "2.6",
            "latest": true
          },
          {
            "title": "2.5.0",
            "path": "2.5",
            "latest": false
          },
          {
            "title": "main",
            "path": "main",
            "latest": false
          }
        ]

        """)
    }

    @Test func aNameUsedByBothSidesIsAnError() throws {
        let directory = TemporaryDirectory()
        directory.write("source/css/x.css", "")
        directory.write("source/new.txt", "")
        directory.write("site/css/other.css", "")
        let error = failure {
            try DocsSite.merge(directory.url.appendingPathComponent("source"), into: directory.url.appendingPathComponent("site"), origin: "docs")
        }
        #expect(error == ToolError(message: "error: docs/css collides with an existing site path"))
    }

    @Test func requiredOptionsAndTheReleasesJSONAreChecked() {
        #expect(failure { try DocsSite.run(["--inputs", "a"]) }?.status == 2)
        #expect(failure { try DocsSite.run(["--inputs", "a", "--releases", "nope", "--output", "b"]) }?.status == 2)
    }
}
