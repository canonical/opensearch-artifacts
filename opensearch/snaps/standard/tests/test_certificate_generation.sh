#!/usr/bin/env bash
# Run on Linux with Bash, OpenSSL and GNU coreutils; no snap or root required.
set -euo pipefail

helper=${1:-$(dirname "$(readlink -f "$0")")/../scripts/helpers/create-certificate.sh}
scratch=$(mktemp -d)
trap 'status=$?; if (( status != 0 )); then cat "$scratch/output" >&2; fi; rm -rf "$scratch"' EXIT
certs=$scratch/certificates
mkdir "$certs"
cd "$scratch"

generate() {
    bash "$helper" --target-dir "$certs" "$@" > "$scratch/output" 2>&1
}

snapshot() {
    (cd "$certs"; sha256sum *.pem *.srl; stat -c '%n %a %u %g' *.pem *.srl) > "$scratch/$1"
}

unchanged() {
    snapshot after
    diff -u "$scratch/before" "$scratch/after"
    local leftovers
    leftovers=$(find "$certs" -mindepth 1 ! -name '*.pem' ! -name '*.srl')
    if [[ -n "$leftovers" ]]; then
        echo 'Temporary certificate files were left behind' >&2
        exit 1
    fi
}

matches() {
    openssl x509 -in "$certs/$1.pem" -pubkey -noout > "$scratch/cert-public"
    openssl pkey -in "$certs/$1-key.pem" -passin "pass:$2" -pubout > "$scratch/key-public"
    cmp "$scratch/cert-public" "$scratch/key-public"
    openssl verify -CAfile "$certs/root-ca.pem" "$certs/$1.pem"
}

generate --type root --password ca-password
generate --type admin --root-password ca-password
generate --type node --name fixture --root-password ca-password
generate --type client --name fixture --subject /CN=fixture --root-password ca-password
chmod 640 "$certs"/*.pem

snapshot before
if generate --type node --name fixture --sans IP:not-an-ip --root-password ca-password; then
    echo 'Invalid SAN was accepted' >&2; exit 1
fi
unchanged
echo 'PASS invalid SAN preserves the pair and cleans temporary files'

snapshot before
if generate --type admin --root-password incorrect-password; then
    echo 'Incorrect CA password was accepted' >&2; exit 1
fi
unchanged
echo 'PASS signing failure preserves the pair'

snapshot before
if generate --type root --subject malformed-subject; then
    echo 'Invalid root subject was accepted' >&2; exit 1
fi
unchanged
echo 'PASS root generation failure preserves the CA'

if (( EUID != 0 )); then
    snapshot before
    chmod 550 "$certs"
    result=0
    generate --type node --name fixture --root-password ca-password || result=$?
    chmod 750 "$certs"
    test "$result" != 0
    unchanged
    echo 'PASS unwritable output directory preserves existing files'
fi

# Real OpenSSL still generates/signs; only the second publication rename fails.
mkdir "$scratch/bin"
real_mv=$(command -v mv)
cat > "$scratch/bin/mv" <<'EOF'
#!/usr/bin/env bash
if [[ "${*: -1}" == "$TEST_CERTS/node-fixture.pem" && ! -e "$TEST_FAIL_MARK" ]]; then
    touch "$TEST_FAIL_MARK"
    exit 1
fi
exec "$TEST_REAL_MV" "$@"
EOF
chmod +x "$scratch/bin/mv"
snapshot before
if PATH="$scratch/bin:$PATH" TEST_CERTS="$certs" TEST_REAL_MV="$real_mv" TEST_FAIL_MARK="$scratch/failed" \
    generate --type node --name fixture --root-password ca-password; then
    echo 'Publication failure was accepted' >&2; exit 1
fi
unchanged
matches node-fixture ''
echo 'PASS publication failure restores both files and their metadata'

# Interrupt after real key generation, before a certificate can be published.
real_openssl=$(command -v openssl)
cat > "$scratch/bin/openssl" <<'EOF'
#!/usr/bin/env bash
"$TEST_REAL_OPENSSL" "$@" || exit
if [[ "$1" == genrsa ]]; then
    kill -TERM "$PPID"
    sleep 1
fi
EOF
chmod +x "$scratch/bin/openssl"
snapshot before
if PATH="$scratch/bin:$PATH" TEST_REAL_OPENSSL="$real_openssl" \
    generate --type node --name fixture --root-password ca-password; then
    echo 'Interrupted generation succeeded' >&2; exit 1
fi
unchanged
echo 'PASS interrupted generation preserves the pair'

for key_password in '' leaf-password; do
    for cert_type in admin node client; do
        extra=()
        resource=$cert_type
        if [[ "$cert_type" != admin ]]; then
            extra=(--name fixture --subject /CN=fixture)
            resource=$cert_type-fixture
        fi
        generate --type "$cert_type" "${extra[@]}" --password "$key_password" --root-password ca-password
        matches "$resource" "$key_password"
        test "$(stat -c %a "$certs/$resource-key.pem")" = 640
    done
done
echo 'PASS encrypted and unencrypted leaf generation preserves permissions'

for ca_password in '' ca-password; do
    generate --type root --password "$ca_password"
    matches root-ca "$ca_password"
done
echo 'PASS encrypted and unencrypted root generation'
