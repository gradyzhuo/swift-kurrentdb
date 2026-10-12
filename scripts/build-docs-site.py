#!/usr/bin/env python3
"""Assemble the GitHub Pages site: the landing page plus one DocC build per version.

    /<base>/                                     landing page (docs/)
    /<base>/documentation/kurrentdb/             latest release
    /<base>/<label>/documentation/kurrentdb/     every release (including the latest) and main
    /<base>/doc-versions.json                    the version menu's entries, newest first

`--inputs` holds one directory per label (`2.5`, ..., `main`), each with the version's
`KurrentDB.symbols.json` and its `KurrentDB.docc` catalog. `--releases` is the output of
scripts/doc-versions.py; `main` is added after the releases.

Every generated page loads `/<base>/doc-versions.js` (from docs/), which draws the menu.

Usage:
  scripts/build-docs-site.py --inputs DIR --releases JSON --output DIR [--docc "xcrun docc"]
"""

import argparse
import json
import shlex
import shutil
import subprocess
import tempfile
from pathlib import Path


def convert(docc: list[str], source: Path, hosting_base_path: str, output: Path) -> None:
    symbol_graphs = Path(tempfile.mkdtemp())
    shutil.copy(source / "KurrentDB.symbols.json", symbol_graphs)
    subprocess.run(
        [
            *docc, "convert", str(source / "KurrentDB.docc"),
            "--additional-symbol-graph-dir", str(symbol_graphs),
            "--fallback-display-name", "KurrentDB",
            "--fallback-bundle-identifier", "KurrentDB",
            "--transform-for-static-hosting",
            "--hosting-base-path", hosting_base_path,
            "--output-path", str(output),
        ],
        check=True,
    )
    shutil.rmtree(symbol_graphs)


def merge(source: Path, destination: Path, origin: str) -> None:
    """Copy `source` into `destination`; a name both sides use is an error, not an overwrite."""
    for entry in source.iterdir():
        target = destination / entry.name
        if target.exists():
            raise SystemExit(f"error: {origin}/{entry.name} collides with an existing site path")
        if entry.is_dir():
            shutil.copytree(entry, target)
        else:
            shutil.copy2(entry, target)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--inputs", type=Path, required=True)
    parser.add_argument("--releases", required=True, help="JSON from scripts/doc-versions.py")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--landing", type=Path, default=Path("docs"))
    parser.add_argument("--base", default="swift-kurrentdb", help="GitHub Pages path of the site")
    parser.add_argument("--docc", default="docc", help='docc command, e.g. "xcrun docc"')
    arguments = parser.parse_args()

    docc = shlex.split(arguments.docc)
    releases = json.loads(arguments.releases)
    versions = [*releases, {"label": "main", "ref": "main"}]
    output: Path = arguments.output
    output.mkdir(parents=True)

    for version in versions:
        label = version["label"]
        convert(docc, arguments.inputs / label, f"{arguments.base}/{label}", output / label)

    # The latest release is also published at the root, so the plain
    # /documentation/kurrentdb/ links always show what users install.
    if releases:
        root = Path(tempfile.mkdtemp())
        convert(docc, arguments.inputs / releases[0]["label"], arguments.base, root / "docc")
        (root / "docc" / "index.html").unlink()  # the landing page owns /index.html
        merge(root / "docc", output, "DocC (latest release)")
        shutil.rmtree(root)

    menu_script = f'<script defer src="/{arguments.base}/doc-versions.js"></script>'
    for page in output.rglob("index.html"):
        html = page.read_text()
        page.write_text(html.replace("</head>", f"{menu_script}</head>", 1))

    entries = [
        {"title": version["ref"], "path": version["label"], "latest": index == 0 and bool(releases)}
        for index, version in enumerate(versions)
    ]
    (output / "doc-versions.json").write_text(json.dumps(entries, indent=2) + "\n")

    merge(arguments.landing, output, str(arguments.landing))


if __name__ == "__main__":
    main()
