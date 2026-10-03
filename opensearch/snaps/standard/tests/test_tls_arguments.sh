#!/usr/bin/env bash

# Run with Bash, GNU getopt, OpenSSL and the packaged yq available.
set -euo pipefail

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
cd "$work"
export OPS_ROOT="$scripts" SNAP_LOG_DIR="$work/logs"
export OPENSEARCH_PATH_CONF="$work/config"
mkdir -p "$OPENSEARCH_PATH_CONF/certificates"
printf '%s\n' '---' > "$OPENSEARCH_PATH_CONF/opensearch.yml"
certs="$OPENSEARCH_PATH_CONF/certificates"
init="$scripts/wrappers/security/tls/self-managed-init.sh"
node="$scripts/wrappers/security/tls/self-managed-node.sh"
helper="$scripts/helpers/create-certificate.sh"

bash "$init" --target-dir "$certs" --root-password test-root --admin-password test-admin
bash "$node" --target-dir "$certs" --name test-node --root-password test-root
find "$OPENSEARCH_PATH_CONF" -type f -exec sha256sum {} + | sort > "$work/before"

reject() {
    if bash "$@" 2>&1 | cat > "$work/output"; then
        cat "$work/output"
        find "$OPENSEARCH_PATH_CONF" -type f -exec sha256sum {} + | sort > "$work/after"
        diff -u "$work/before" "$work/after" || true
        echo "FAIL: accepted malformed arguments: $*" >&2
        exit 1
    fi
    find "$OPENSEARCH_PATH_CONF" -type f -exec sha256sum {} + | sort > "$work/after"
    diff -u "$work/before" "$work/after"
}

for option in root-password admin-password root-subject admin-subject rest-with-tls target-dir; do
    reject "$init" --target-dir "$certs" "--$option"
done
reject "$init" --target-dir "$certs" --unknown-option
for option in name root-password node-password node-subject sans rest-with-tls target-dir; do
    reject "$node" --target-dir "$certs" --name test-node --root-password test-root "--$option"
done
reject "$node" --target-dir "$certs" --name test-node --root-password test-root --unknown-option
reject "$node" --target-dir "$certs" --name ''
for option in password root-password type name subject sans target-dir; do
    reject "$helper" --target-dir "$certs" --type root "--$option"
done
reject "$helper" --target-dir "$certs" --type root --unknown-option

for script in "$init" "$node" "$helper"; do
    bash "$script" --help 2>&1 | cat > "$work/output"
    grep -q 'usage:' "$work/output"
    reject "$script" --help --unknown-option
done

# Explicit empty passwords are valid and keep the existing unencrypted-key UX.
mkdir -p "$work/empty/certificates"
printf '%s\n' '---' > "$work/empty/opensearch.yml"
OPENSEARCH_PATH_CONF="$work/empty" bash "$init" --target-dir="$work/empty/certificates" --root-password= --admin-password=
openssl pkey -in "$work/empty/certificates/root-ca-key.pem" -passin pass: -noout
OPENSEARCH_PATH_CONF="$work/empty" bash "$node" --target-dir="$work/empty/certificates" --name=empty-password --node-password=
openssl pkey -in "$work/empty/certificates/node-empty-password-key.pem" -passin pass: -noout
echo 'PASS: TLS arguments reject errors without changing certificates or configuration'
