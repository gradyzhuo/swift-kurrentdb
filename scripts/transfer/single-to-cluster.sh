#!/usr/bin/env bash
#
# Copy KurrentDB data from a single-node deployment into node1's volume of the
# 3-node cluster defined in server/docker-compose.yaml.
#
# Only node1 receives the data. node2/node3 must join afterwards and catch up
# via replication -- copying the same data independently into every node is
# not a supported migration path and can cause epoch/truncation conflicts
# during cluster election.
#
# Usage:
#   single-to-cluster.sh --source <docker-volume|host-path> [--target <docker-volume>] [--force]
#
# Examples:
#   single-to-cluster.sh --source kurrentdb-single-data --target node1-data
#   single-to-cluster.sh --source /mnt/old-kurrentdb-data --target node1-data

set -euo pipefail

SOURCE=""
TARGET="node1-data"
FORCE=0

usage() {
  cat <<'EOF'
Usage: single-to-cluster.sh --source <docker-volume|host-path> [--target <docker-volume>] [--force]

  --source <volume|path>  Docker volume name OR host directory path holding the
                          single-node KurrentDB data (required)
  --target <volume>       Docker volume for the cluster's node1 (default: node1-data)
  --force                 Skip the "volume already has data" / "still in use" safety checks
  -h, --help              Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$SOURCE" ]]; then
  echo "Error: --source <docker-volume|host-path> is required" >&2
  usage
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Error: docker is not installed or not on PATH" >&2
  exit 1
fi

# --source may be a docker volume name or a host directory path; figure out which.
if docker volume inspect "$SOURCE" >/dev/null 2>&1; then
  SOURCE_KIND="volume"
elif [[ -d "$SOURCE" ]]; then
  SOURCE_KIND="path"
  SOURCE="$(cd "$SOURCE" && pwd)"
else
  echo "Error: source '$SOURCE' is neither an existing docker volume nor a directory path" >&2
  exit 1
fi

if ! docker volume inspect "$TARGET" >/dev/null 2>&1; then
  echo "Target volume '$TARGET' does not exist yet, creating it..."
  docker volume create "$TARGET" >/dev/null
fi

in_use_by() {
  docker ps --filter "volume=$1" --format '{{.Names}}'
}

if [[ $FORCE -eq 0 ]]; then
  if [[ "$SOURCE_KIND" == "volume" ]]; then
    source_users="$(in_use_by "$SOURCE")"
    if [[ -n "$source_users" ]]; then
      echo "Error: source volume '$SOURCE' is mounted by a running container: $source_users" >&2
      echo "Stop it first so the data is flushed and not being written during the copy, or pass --force." >&2
      exit 1
    fi
  else
    echo "Warning: source is a host path -- make sure no process (e.g. a running KurrentDB container bind-mounting it) is still writing to '$SOURCE' before continuing." >&2
  fi

  target_users="$(in_use_by "$TARGET")"
  if [[ -n "$target_users" ]]; then
    echo "Error: target volume '$TARGET' is mounted by a running container: $target_users" >&2
    echo "Stop it first, or pass --force." >&2
    exit 1
  fi

  target_size="$(docker run --rm -v "$TARGET:/to" alpine sh -c 'du -s /to 2>/dev/null | cut -f1')"
  if [[ "${target_size:-0}" -gt 0 ]]; then
    echo "Error: target volume '$TARGET' already contains data. Refusing to overwrite." >&2
    echo "Remove/rename it first, or pass --force to overwrite anyway." >&2
    exit 1
  fi
fi

echo "Copying '$SOURCE' -> '$TARGET'..."
docker run --rm \
  -v "$SOURCE:/from:ro" \
  -v "$TARGET:/to" \
  alpine sh -c 'cp -a /from/. /to/'

echo "Done. Target volume size:"
docker run --rm -v "$TARGET:/to" alpine du -sh /to

cat <<EOF

Next steps:
  1. cd server && docker compose up -d node1.kurrentdb
  2. Wait until node1 reports healthy (docker compose ps)
  3. docker compose up -d node2.kurrentdb node3.kurrentdb
     -> they will join the cluster and replicate data from node1 automatically.
EOF
