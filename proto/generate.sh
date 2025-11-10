#!/bin/bash
## Copyright 2024, gRPC Authors All rights reserved.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.

set -eu

here="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
root="$here/.."
protoc=$(which protoc)

# Checkout and build the plugins.
build_dir=$(mktemp -d)
git clone https://github.com/grpc/grpc-swift-protobuf --depth 1 "$build_dir"
swift build --package-path "$build_dir" --product protoc-gen-swift
swift build --package-path "$build_dir" --product protoc-gen-grpc-swift-2

# Grab the plugin paths.
bin_path=$(swift build --package-path "$build_dir" --show-bin-path)
protoc_gen_swift="$bin_path/protoc-gen-swift"
protoc_gen_grpc_swift="$bin_path/protoc-gen-grpc-swift-2"

# Generates gRPC by invoking protoc with the gRPC Swift plugin.
# Parameters:
# - $1: .proto file
# - $2: proto path
# - $3: output path
# - $4 onwards: options to forward to the plugin
function generate_grpc {
  local proto=$1
  local args=("--plugin=$protoc_gen_grpc_swift" "--proto_path=${2}" "--grpc-swift-2_out=${3}")

  for option in "${@:4}"; do
    args+=("--grpc-swift-2_opt=$option")
  done

  invoke_protoc "${args[@]}" "$proto"
}

# Generates messages by invoking protoc with the Swift plugin.
# Parameters:
# - $1: .proto file
# - $2: proto path
# - $3: output path
# - $4 onwards: options to forward to the plugin
function generate_message {
  local proto=$1
  local args=("--plugin=$protoc_gen_swift" "--proto_path=$2" "--swift_out=$3")

  for option in "${@:4}"; do
    args+=("--swift_opt=$option")
  done

  invoke_protoc "${args[@]}" "$proto"
}

function invoke_protoc {
  # Setting -x when running the script produces a lot of output, instead boil
  # just echo out the protoc invocations.
  echo "$protoc" "$@"
  "$protoc" "$@"
}

#- EXAMPLES -------------------------------------------------------------------

function generate_eventstore_client {
  local proto="$here/$1.proto"
  local output="$root/Sources/GRPCEncapsulates/Generated"

  generate_message "$proto" "$(dirname "$proto")" "$output" "Visibility=Package"
  generate_grpc "$proto" "$(dirname "$proto")" "$output" "Visibility=Package"
}

#------------------------------------------------------------------------------

mkdir -p "$root/Sources/GRPCEncapsulates/Generated"

# Generate examples
generate_eventstore_client "code"
generate_eventstore_client "status"
generate_eventstore_client "cluster"
generate_eventstore_client "gossip"
generate_eventstore_client "monitoring"
generate_eventstore_client "operations"
generate_eventstore_client "persistent"
generate_eventstore_client "projections"
generate_eventstore_client "redaction"
generate_eventstore_client "serverfeatures"
generate_eventstore_client "shared"
generate_eventstore_client "status"
generate_eventstore_client "streams"
generate_eventstore_client "users"

