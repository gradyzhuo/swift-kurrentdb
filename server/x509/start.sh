#!/usr/bin/env bash
# Starts a single KurrentDB node that accepts X.509 user certificates, for X509Tests.
#
# User certificate authentication is a licensed KurrentDB feature: the node refuses to
# start without a valid key in KURRENTDB_LICENSE_KEY.
#
# Writes to $CERTS_DIR (default: server/x509/certs):
#   ca/ca.crt, ca/ca.key         CA shared by the node and the user
#   node/node.crt, node/node.key node certificate (localhost, 127.0.0.1)
#   user-admin/user.crt, .key    user certificate for `admin` (CN = username, ClientAuth EKU)
#
# Then run:
#   KURRENTDB_X509_CERTS_DIR=server/x509/certs KURRENTDB_X509_PORT=2116 \
#     swift test --filter X509Tests
set -euo pipefail

: "${KURRENTDB_LICENSE_KEY:?KURRENTDB_LICENSE_KEY must be set: user certificates are a licensed KurrentDB feature}"

here="$(cd "$(dirname "$0")" && pwd)"
image="${KURRENTDB_IMAGE:-docker.kurrent.io/kurrent-latest/kurrentdb:26.1}"
port="${KURRENTDB_X509_PORT:-2116}"
certs="${CERTS_DIR:-$here/certs}"
name="kurrentdb-x509"

rm -rf "$certs"
mkdir -p "$certs"

# CA and node certificate, the same way server/docker-compose.yaml makes them.
docker run --rm --user "$(id -u):$(id -g)" -v "$certs:/certs" -w /certs \
    --entrypoint bash eventstore/es-gencert-cli:1.0.2 -c \
    "es-gencert-cli create-ca \
     && es-gencert-cli create-node -out ./node -ip-addresses 127.0.0.1 -dns-names localhost"

# User certificate. es-gencert-cli 1.0.2 (the newest on Docker Hub) has no create-user,
# so sign it with openssl: CN is the username, ClientAuth only (no ServerAuth).
mkdir -p "$certs/user-admin"
openssl req -new -newkey rsa:2048 -nodes \
    -keyout "$certs/user-admin/user.key" \
    -out "$certs/user-admin/user.csr" \
    -subj "/CN=admin"
openssl x509 -req -in "$certs/user-admin/user.csr" \
    -CA "$certs/ca/ca.crt" -CAkey "$certs/ca/ca.key" -CAcreateserial \
    -out "$certs/user-admin/user.crt" -days 2 -sha256 \
    -extfile <(printf "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth\n")
chmod 644 "$certs"/*/*

docker rm -f "$name" >/dev/null 2>&1 || true
docker run -d --name "$name" -p "$port:2113" -v "$certs:/certs:ro" \
    -e KURRENTDB_CLUSTER_SIZE=1 \
    -e KURRENTDB_TRUSTED_ROOT_CERTIFICATES_PATH=/certs/ca \
    -e KURRENTDB_CERTIFICATE_FILE=/certs/node/node.crt \
    -e KURRENTDB_CERTIFICATE_PRIVATE_KEY_FILE=/certs/node/node.key \
    -e KURRENTDB_ADVERTISE_HOST_TO_CLIENT_AS=127.0.0.1 \
    -e KURRENTDB_ADVERTISE_NODE_PORT_TO_CLIENT_AS="$port" \
    -e KURRENTDB_USER_CERTIFICATES__ENABLED=true \
    -e KURRENTDB_LICENSING__LICENSE_KEY="$KURRENTDB_LICENSE_KEY" \
    "$image" >/dev/null

for _ in $(seq 1 60); do
    if curl --silent --fail --cacert "$certs/ca/ca.crt" "https://localhost:$port/health/live" >/dev/null; then
        echo "KurrentDB with user certificates is up on localhost:$port"
        exit 0
    fi
    sleep 2
done

echo "KurrentDB did not become healthy" >&2
docker logs "$name" >&2
exit 1
