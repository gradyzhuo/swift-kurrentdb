#!/usr/bin/env bash
# Regenerates Sources/_GRPCProtobufGenerated from every proto/**/*.proto with pinned generators.
#
# Usage: scripts/regenerate-protos.sh [--output DIR] [--generators DIR]
#
#   --output DIR      where the .pb.swift and .grpc.swift files go
#                     (default: Sources/_GRPCProtobufGenerated). Once protoc succeeds,
#                     the *.pb.swift and *.grpc.swift files in DIR are replaced, so a
#                     deleted proto leaves no stale output; on failure DIR is untouched.
#   --generators DIR  where the two protoc plugins are built and kept
#                     (default: .build/generators). A plugin already there for the
#                     pinned version is reused.
#
# Requires protoc >= 3.15 on PATH, git and a Swift toolchain that can build
# grpc-swift-protobuf (tools 6.1 or later). See proto/README.md.
set -euo pipefail

SWIFT_PROTOBUF_VERSION=1.37.0        # keep equal to the swift-protobuf floor in Package.swift
GRPC_SWIFT_PROTOBUF_VERSION=2.4.1    # the grpc-swift-protobuf tag whose plugin generated Sources/_GRPCProtobufGenerated
# protoc-gen-grpc-swift-2 takes its code generator (GRPCCodeGen) from grpc-swift-2 and its proto
# naming from swift-protobuf's plugin library; the tag does not pin either, so the script does.
GRPC_PLUGIN_GRPC_SWIFT_2_VERSION=2.4.4
GRPC_PLUGIN_SWIFT_PROTOBUF_VERSION=1.39.0

usage() {
    sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
}

die() {
    echo "regenerate-protos: $1" >&2
    exit "${2:-1}"
}

root="$(cd "$(dirname "$0")/.." && pwd)"
output=""
generators=""

while [ $# -gt 0 ]; do
    case "$1" in
        --output)
            [ $# -ge 2 ] || die "--output needs a directory" 64
            output="$2"
            shift 2
            ;;
        --generators)
            [ $# -ge 2 ] || die "--generators needs a directory" 64
            generators="$2"
            shift 2
            ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "unknown argument: $1" 64
            ;;
    esac
done

# Resolve both directories against the caller's working directory, then make them absolute.
mkdir -p "${output:-$root/Sources/_GRPCProtobufGenerated}" "${generators:-$root/.build/generators}"
output="$(cd "${output:-$root/Sources/_GRPCProtobufGenerated}" && pwd)"
generators="$(cd "${generators:-$root/.build/generators}" && pwd)"

# protoc >= 3.15 (proto3 `optional`). `protoc --version` prints e.g. "libprotoc 3.21.12" or "libprotoc 34.1".
protoc_hint="install it with 'brew install protobuf' or 'apt-get install protobuf-compiler libprotobuf-dev'"
command -v protoc >/dev/null 2>&1 || die "protoc not found on PATH; $protoc_hint" 2
protoc_version="$(protoc --version 2>/dev/null | awk '{ print $2 }')" || protoc_version=""
protoc_major="${protoc_version%%.*}"
protoc_minor="${protoc_version#*.}"
protoc_minor="${protoc_minor%%.*}"
case "$protoc_version" in
    *.*) ;;
    *) protoc_major="" ;;
esac
case "$protoc_major" in
    "" | *[!0-9]*) die "cannot read a version from 'protoc --version'; $protoc_hint" 2 ;;
esac
case "$protoc_minor" in
    "" | *[!0-9]*) die "cannot read a version from 'protoc --version'; $protoc_hint" 2 ;;
esac
if [ "$protoc_major" -lt 3 ] || { [ "$protoc_major" -eq 3 ] && [ "$protoc_minor" -lt 15 ]; }; then
    die "protoc $protoc_version is older than 3.15; $protoc_hint" 2
fi

# Scratch space, removed on every exit: protoc writes here first, so a failure leaves --output untouched.
scratch="$(mktemp -d "${TMPDIR:-/tmp}/regenerate-protos.XXXXXX")"
partial=""
cleanup() {
    rm -rf "$scratch"
    if [ -n "$partial" ]; then rm -f "$partial"; fi
}
trap cleanup EXIT

# build_plugin NAME VERSION REPOSITORY PRODUCT [DEPENDENCY@VERSION ...]: sets `plugin` to the path of
# the plugin binary, building it if needed with each listed dependency resolved at exactly that version.
# Called directly (not in a command substitution) so that `set -e` stops the script on any failure;
# the binary reaches its cached name only after a successful build.
build_plugin() {
    local name="$1" version="$2" repository="$3" product="$4"
    shift 4
    local tag="$version" pin
    for pin in "$@"; do
        tag="$tag+$pin"
    done
    local binary="$generators/$product-$tag"
    if [ ! -x "$binary" ]; then
        local source="$generators/src/$name-$tag"
        local bin_path
        rm -rf "$source"
        echo "Building $product $tag ..." >&2
        git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$version" "$repository" "$source" >&2
        # `resolve NAME --version` only moves a dependency that is already resolved.
        swift package --package-path "$source" resolve >&2
        for pin in "$@"; do
            swift package --package-path "$source" resolve "${pin%@*}" --version "${pin#*@}" >&2
        done
        swift build -c release --package-path "$source" --product "$product" >&2
        bin_path="$(swift build -c release --package-path "$source" --show-bin-path)"
        partial="$binary.partial"
        cp "$bin_path/$product" "$partial"
        mv "$partial" "$binary"
        partial=""
    fi
    plugin="$binary"
}

plugin=""
build_plugin swift-protobuf "$SWIFT_PROTOBUF_VERSION" \
    https://github.com/apple/swift-protobuf.git protoc-gen-swift
protoc_gen_swift="$plugin"
build_plugin grpc-swift-protobuf "$GRPC_SWIFT_PROTOBUF_VERSION" \
    https://github.com/grpc/grpc-swift-protobuf.git protoc-gen-grpc-swift-2 \
    "grpc-swift-2@$GRPC_PLUGIN_GRPC_SWIFT_2_VERSION" "swift-protobuf@$GRPC_PLUGIN_SWIFT_PROTOBUF_VERSION"
protoc_gen_grpc_swift="$plugin"

cd "$root"
files=()
while IFS= read -r file; do
    files+=("$file")
done < <(find proto -name '*.proto' | LC_ALL=C sort)
[ ${#files[@]} -gt 0 ] || die "no .proto files under proto/"

protoc --plugin=protoc-gen-swift="$protoc_gen_swift" \
    --swift_out="$scratch" --proto_path=proto \
    --swift_opt=Visibility=package --swift_opt=FileNaming=PathToUnderscores "${files[@]}"
protoc --plugin=protoc-gen-grpc-swift-2="$protoc_gen_grpc_swift" \
    --grpc-swift-2_out="$scratch" --proto_path=proto \
    --grpc-swift-2_opt=Visibility=Package --grpc-swift-2_opt=Server=False --grpc-swift-2_opt=FileNaming=PathToUnderscores "${files[@]}"

# Both runs succeeded: replace the generated files in the output directory.
rm -f "$output"/*.pb.swift "$output"/*.grpc.swift
cp "$scratch"/*.pb.swift "$scratch"/*.grpc.swift "$output"/

echo "protoc $protoc_version, protoc-gen-swift $SWIFT_PROTOBUF_VERSION, protoc-gen-grpc-swift-2 $GRPC_SWIFT_PROTOBUF_VERSION"
echo "Generated ${#files[@]} protos into $output"
