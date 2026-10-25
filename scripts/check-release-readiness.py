#!/usr/bin/env python3
"""Check that the documentation is ready for the release a `pre/X.Y.Z` tag announces.

A release is open while a `pre/X.Y.Z` tag exists and the `X.Y.Z` tag does not. The release tag
locks the DocC catalog and the README into `/X.Y/` and the site root for good, and the landing
page must flip to the new version in the same release, so this script checks the mechanical
rows of the release checklist on every push and prints one line per check:

    ok       README.md: from: "2.7.0"
    missing  docs/index.html: <option value="v2.7"> is the first option and marked (latest)

What it cannot check is whether each What's new bullet is also documented in the article that
covers the behaviour; that stays a review step.

Exit status: 0 when nothing is missing or no release is open. When something is missing:
1 with --strict (the Prepare PR itself and release tags), otherwise 0 with GitHub `::warning::`
annotations so the gap is visible on every run without failing unrelated work.

Usage: scripts/check-release-readiness.py [--version X.Y.Z] [--strict] [--root DIR]
"""

import argparse
import html
import re
import subprocess
import sys
from pathlib import Path

RELEASE_TAG = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")
PRE_TAG = re.compile(r"^pre/(\d+\.\d+\.\d+)$")

README = "README.md"
GETTING_STARTED = "Sources/KurrentDB/KurrentDB.docc/Articles/Getting started.md"
WHATS_NEW = "Sources/KurrentDB/KurrentDB.docc/Documentation.md"
LANDING_PAGE = "docs/index.html"


def git_tags(root: Path) -> list[str]:
    result = subprocess.run(["git", "tag", "--list"], cwd=root, check=True, capture_output=True, text=True)
    return result.stdout.split()


def open_releases(tags: list[str]) -> list[str]:
    """Versions announced by a `pre/` tag whose release tag does not exist yet, oldest first."""
    released = {tag for tag in tags if RELEASE_TAG.match(tag)}
    announced = [match.group(1) for match in map(PRE_TAG.match, tags) if match]
    return sorted((version for version in announced if version not in released), key=version_key)


def version_key(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def read(root: Path, relative: str) -> str:
    path = root / relative
    return path.read_text(encoding="utf-8") if path.exists() else ""


def checks(root: Path, version: str) -> list[tuple[bool, str]]:
    """Every (passed, description) pair for `version`, in checklist order."""
    major, minor, patch = version_key(version)
    series = f"{major}.{minor}"
    results: list[tuple[bool, str]] = []

    def check(passed: bool, file: str, what: str) -> None:
        results.append((passed, f"{file}: {what}"))

    pin = f'from: "{version}"'
    check(pin in read(root, README), README, pin)
    check(pin in read(root, GETTING_STARTED), GETTING_STARTED, pin)

    whats_new = read(root, WHATS_NEW).split("## What's new", 1)
    section = whats_new[1] if len(whats_new) == 2 else ""
    headings = re.findall(r"^### (\S+)", section, re.MULTILINE)
    check(bool(headings) and headings[0] == series, WHATS_NEW, f"first heading under What's new is ### {series}")
    if patch > 0:
        own = re.split(r"^### ", section, flags=re.MULTILINE)
        entry = next((part for part in own if part.startswith(series + "\n") or part.startswith(series + " ")), "")
        check(f"({version})" in entry, WHATS_NEW, f"a bullet under ### {series} ends with ({version})")

    page = html.unescape(read(root, LANDING_PAGE))
    check(pin in page, LANDING_PAGE, pin)

    picker = page.split('id="release-select"', 1)
    first_option = re.search(r"<option [^>]*>", picker[1]) if len(picker) == 2 else None
    check(
        first_option is not None
        and f'value="v{series}"' in first_option.group(0)
        and "(latest)" in first_option.group(0),
        LANDING_PAGE,
        f'<option value="v{series}"> is the first option and marked (latest)',
    )

    article = re.search(rf'<article class="release" id="v{re.escape(series)}">(.*?)</article>', page, re.DOTALL)
    check(article is not None, LANDING_PAGE, f'<article class="release" id="v{series}">')
    latest_tags = re.findall(r'<div class="whats-new-tag">(.*?)</div>', page, re.DOTALL)
    latest = [tag for tag in latest_tags if "Latest ·" in tag]
    check(
        len(latest) == 1 and f"Latest · v{version}" in latest[0] and article is not None and latest[0] in article.group(1),
        LANDING_PAGE,
        f'exactly one "Latest · vX.Y.Z" tag, on the v{series} article, saying Latest · v{version}',
    )
    check(
        article is not None and f"releases/tag/{version}" in article.group(1),
        LANDING_PAGE,
        f"the v{series} article links to releases/tag/{version}",
    )
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--version", help="release to check; default: every open pre/X.Y.Z tag")
    parser.add_argument("--strict", action="store_true", help="exit 1 when something is missing")
    parser.add_argument("--root", default=".", help="repository root")
    arguments = parser.parse_args()
    root = Path(arguments.root)

    if arguments.version:
        if not RELEASE_TAG.match(arguments.version):
            parser.error(f"--version must be X.Y.Z, got {arguments.version!r}")
        versions = [arguments.version]
    else:
        versions = open_releases(git_tags(root))
        if not versions:
            print("no release open: no pre/X.Y.Z tag without its X.Y.Z tag")
            return 0

    missing = 0
    for version in versions:
        print(f"release {version}")
        for passed, description in checks(root, version):
            print(f"  {'ok     ' if passed else 'missing'}  {description}")
            if not passed:
                missing += 1
                file = description.split(":", 1)[0]
                level = "error" if arguments.strict else "warning"
                print(f"::{level} file={file}::release {version}: missing {description}")
    if missing:
        print(f"{missing} missing", file=sys.stderr)
    return 1 if missing and arguments.strict else 0


if __name__ == "__main__":
    sys.exit(main())
