#!/usr/bin/env bash

# Exercise the parser without uploading security settings to a live cluster.
set -eu

scripts=$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export OPS_ROOT="$scripts" SNAP_LOG_DIR="$work/logs"
export OPENSEARCH_PATH_CONF="$work/config" OPENSEARCH_PATH_CERTS="$work/certificates"
export OPENSEARCH_PLUGINS="$work/plugins" SECURITY_ADMIN_MARKER="$work/upload"
mkdir -p "$OPENSEARCH_PLUGINS/opensearch-security/tools"
cat > "$OPENSEARCH_PLUGINS/opensearch-security/tools/securityadmin.sh" <<'EOF'
printf '%s\n' "$@" > "$SECURITY_ADMIN_MARKER"
EOF

script="$scripts/wrappers/security-init.sh"
reject() {
    rm -f "$SECURITY_ADMIN_MARKER"
    if bash "$script" "$@" > "$work/output" 2>&1; then
        cat "$work/output"
        echo "FAIL: accepted malformed arguments: $*" >&2
        exit 1
    fi
    test ! -e "$SECURITY_ADMIN_MARKER"
}

reject --unknown-option
reject --tls-priv-key-admin-pass
reject --tls-priv-key-admin-pass=test-password --unknown-option
reject --tls-priv-key-admin-pass test-password --unknown-option
reject tls-priv-key-admin-pass --tls-priv-key-admin-pass=test-password
reject --tls-priv-key-admin-pass=test-password stray
reject --tls-priv-key-admin-pass=test-password -- stray
reject stray --
reject -- stray
bash "$script" --help > "$work/output"
grep -q 'usage:' "$work/output"
test ! -e "$SECURITY_ADMIN_MARKER"
# Preserve the existing early help behavior even alongside malformed arguments.
bash "$script" --help --unknown-option > "$work/output"
test ! -e "$SECURITY_ADMIN_MARKER"

for form in separate equals empty omitted end-marker; do
    args=()
    case "$form" in
        separate) args=(--tls-priv-key-admin-pass test-password) ;;
        equals) args=(--tls-priv-key-admin-pass=test-password) ;;
        empty) args=(--tls-priv-key-admin-pass=) ;;
        end-marker) args=(--) ;;
    esac
    bash "$script" "${args[@]}" > "$work/output"
    test -s "$SECURITY_ADMIN_MARKER"
    if [ "$form" = separate ] || [ "$form" = equals ]; then
        grep -qx -- '-keypass' "$SECURITY_ADMIN_MARKER"
        grep -qx 'test-password' "$SECURITY_ADMIN_MARKER"
    else
        ! grep -qx -- '-keypass' "$SECURITY_ADMIN_MARKER"
    fi
done
echo 'PASS: security-init rejects errors before securityadmin and preserves valid arguments'
