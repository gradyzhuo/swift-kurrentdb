#!/usr/bin/env bash
# Generates the documentation snippets and compiles them.
# Prints each error as `path/to/file.md:line:col: message`; exits non-zero on failure.
set -uo pipefail
cd "$(dirname "$0")/.."
root="$(pwd)"
python3 scripts/generate-doc-snippets.py || exit 1
log="$(mktemp)"
swift build --target DocSnippetsTests >"$log" 2>&1
status=$?
if [ $status -ne 0 ]; then
    # Strip colours, keep diagnostics that point into the repository, make them relative.
    sed -E $'s/\x1b\\[[0-9;]*m//g' "$log" \
        | grep -oE "(error: )?${root}/[^ ]+( [^:]*)*\.(md|swift):[0-9]+:[0-9]+:? (error: )?[^|]*" \
        | sed -E "s#^error: ##; s#${root}/##; s#: FixIt\(.*##" \
        | sort -u
    [ -s "$log" ] && ! grep -qE "${root}/.*\.(md|swift):" "$log" && tail -20 "$log"
fi
rm -f "$log"
exit $status
