#!/usr/bin/env python3
"""Tests for check-release-readiness.py (run with `python3 -m unittest scripts/test_check_release_readiness.py`)."""

import importlib.util
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().with_name("check-release-readiness.py")
spec = importlib.util.spec_from_file_location("readiness", SCRIPT)
readiness = importlib.util.module_from_spec(spec)
spec.loader.exec_module(readiness)


def write(root: Path, relative: str, text: str) -> None:
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def landing_page(latest: str, previous: str, latest_series: str, previous_series: str) -> str:
    return f"""<pre><code>.package(url: "x", from: "{latest}")</code></pre>
<select id="release-select">
  <option value="v{latest_series}" data-en="{latest_series} (latest)">{latest_series} (latest)</option>
  <option value="v{previous_series}" data-en="{previous_series}">{previous_series}</option>
</select>
<article class="release" id="v{latest_series}">
  <div class="whats-new-tag"><span lang="en">Latest &middot; v{latest}</span></div>
  <a href="https://github.com/x/releases/tag/{latest}">notes</a>
</article>
<article class="release" id="v{previous_series}">
  <div class="whats-new-tag">v{previous}</div>
  <a href="https://github.com/x/releases/tag/{previous}">notes</a>
</article>
"""


def ready_tree(root: Path, version: str = "2.7.0") -> None:
    series = version.rsplit(".", 1)[0]
    write(root, readiness.README, f'.package(url: "x", from: "{version}")\n')
    write(root, readiness.GETTING_STARTED, f'.package(url: "x", from: "{version}")\n')
    write(
        root,
        readiness.WHATS_NEW,
        f"# KurrentDB\n\n## What's new\n\n### {series}\n\n- **Thing.** Done ({version}).\n\n### 2.6\n\n- Old.\n",
    )
    write(root, readiness.LANDING_PAGE, landing_page(version, "2.6.0", series, "2.6"))


def failures(root: Path, version: str) -> list[str]:
    return [description for passed, description in readiness.checks(root, version) if not passed]


class ChecksTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)

    def test_ready_minor_passes_every_check(self):
        ready_tree(self.root, "2.7.0")
        self.assertEqual(failures(self.root, "2.7.0"), [])

    def test_ready_patch_passes_with_its_bullet(self):
        ready_tree(self.root, "2.7.1")
        self.assertEqual(failures(self.root, "2.7.1"), [])

    def test_patch_needs_a_bullet_naming_it(self):
        ready_tree(self.root, "2.7.1")
        write(self.root, readiness.WHATS_NEW, "## What's new\n\n### 2.7\n\n- **Thing.** Done.\n")
        self.assertEqual(
            failures(self.root, "2.7.1"),
            [f"{readiness.WHATS_NEW}: a bullet under ### 2.7 ends with (2.7.1)"],
        )

    def test_untouched_tree_reports_every_surface(self):
        ready_tree(self.root, "2.6.0")
        missing = failures(self.root, "2.7.0")
        files = {description.split(":", 1)[0] for description in missing}
        self.assertEqual(
            files, {readiness.README, readiness.GETTING_STARTED, readiness.WHATS_NEW, readiness.LANDING_PAGE}
        )
        self.assertEqual(len(missing), 8)

    def test_landing_page_latest_must_move_to_the_new_article(self):
        ready_tree(self.root, "2.7.0")
        page = (self.root / readiness.LANDING_PAGE).read_text()
        # The new article exists, but the previous one still carries the Latest tag.
        page = page.replace("Latest &middot; v2.7.0", "v2.7.0").replace('tag">v2.6.0', 'tag">Latest · v2.6.0')
        write(self.root, readiness.LANDING_PAGE, page)
        self.assertEqual(
            failures(self.root, "2.7.0"),
            [f'{readiness.LANDING_PAGE}: exactly one "Latest · vX.Y.Z" tag, on the v2.7 article, saying Latest · v2.7.0'],
        )

    def test_landing_page_new_option_must_come_first(self):
        ready_tree(self.root, "2.7.0")
        page = (self.root / readiness.LANDING_PAGE).read_text()
        lines = page.splitlines()
        first, second = lines.index('  <option value="v2.7" data-en="2.7 (latest)">2.7 (latest)</option>'), None
        second = first + 1
        lines[first], lines[second] = lines[second], lines[first]
        write(self.root, readiness.LANDING_PAGE, "\n".join(lines) + "\n")
        self.assertEqual(
            failures(self.root, "2.7.0"),
            [f'{readiness.LANDING_PAGE}: <option value="v2.7"> is the first option and marked (latest)'],
        )

    def test_whats_new_heading_must_be_first(self):
        ready_tree(self.root, "2.7.0")
        write(self.root, readiness.WHATS_NEW, "## What's new\n\n### 2.6\n\n- Old.\n\n### 2.7\n\n- New.\n")
        self.assertEqual(
            failures(self.root, "2.7.0"),
            [f"{readiness.WHATS_NEW}: first heading under What's new is ### 2.7"],
        )


class OpenReleasesTests(unittest.TestCase):
    def test_pre_tag_without_release_tag_is_open(self):
        self.assertEqual(readiness.open_releases(["2.6.0", "pre/2.7.0"]), ["2.7.0"])

    def test_release_tag_closes_it(self):
        self.assertEqual(readiness.open_releases(["2.6.0", "pre/2.7.0", "2.7.0"]), [])

    def test_other_tags_are_ignored_and_order_is_by_version(self):
        tags = ["archive/main-before-rewrite", "pre/2.10.0", "pre/2.7.1", "2.0.0-beta.5", "pre/x"]
        self.assertEqual(readiness.open_releases(tags), ["2.7.1", "2.10.0"])


class CommandLineTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        env = {**os.environ, "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t", "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t"}
        for command in (["git", "init", "-q"], ["git", "commit", "-q", "--allow-empty", "-m", "init"]):
            subprocess.run(command, cwd=self.root, check=True, env=env)

    def run_script(self, *arguments: str) -> subprocess.CompletedProcess:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--root", str(self.root), *arguments], capture_output=True, text=True
        )

    def test_no_open_release_is_a_no_op(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0)
        self.assertIn("no release open", result.stdout)

    def test_open_release_warns_by_default_and_fails_with_strict(self):
        subprocess.run(["git", "tag", "pre/2.7.0"], cwd=self.root, check=True)
        ready_tree(self.root, "2.6.0")
        lenient = self.run_script()
        self.assertEqual(lenient.returncode, 0)
        self.assertIn("::warning file=README.md::release 2.7.0: missing", lenient.stdout)
        strict = self.run_script("--strict")
        self.assertEqual(strict.returncode, 1)
        self.assertIn("::error file=README.md::", strict.stdout)

    def test_explicit_version_ignores_tags(self):
        ready_tree(self.root, "2.7.0")
        result = self.run_script("--version", "2.7.0", "--strict")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotIn("missing", result.stdout)

    def test_version_must_be_a_release_number(self):
        result = self.run_script("--version", "pre/2.7.0")
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()
