#!/usr/bin/env bash
# @nonexhaustive is only observable from another package: Consumer (with @unknown default) must
# build; ConsumerExhaustive (without it) must fail with the one diagnostic that proves the attribute
# is in effect — any other failure is not the expected one. Swift 6.2.3 and later only: on an older
# toolchain ConsumerExhaustive builds and this script exits 1.
set -euo pipefail
export NO_COLOR=1
cd "$(dirname "$0")"
swift build --target Consumer
if swift build --target ConsumerExhaustive 2>&1 | tee exhaustive.log; then
  echo "ConsumerExhaustive built: @nonexhaustive is not in effect" >&2; exit 1
fi
grep -F "error: switch covers known cases, but 'Streams<SpecifiedStream>.Subscription.Message' may have additional unknown values, possibly added in future versions" exhaustive.log
