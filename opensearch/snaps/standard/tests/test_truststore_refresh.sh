#!/usr/bin/env bash
# Run as root inside the setup snap shell, with this source tree in SNAP_COMMON.
set -euo pipefail

standard=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
installed_snap=${SNAP:?Run inside the installed snap shell}
keytool="${JAVA_HOME}/bin/keytool"
work=$(mktemp -d "${SNAP_COMMON}/truststore-test.XXXXXXXX")
trap 'rm -rf -- "$work"' EXIT
cd "$work"

# Keep the real hook away from the running node's plugins and configuration.
export SNAP="$work/snap" SNAP_CURRENT="$work/snap" SNAP_DATA="$work/revision"
export OPS_ROOT="$standard/scripts" SNAP_LOG_DIR="$work/logs"
export OPENSEARCH_PATH_CONF="$work/config" OPENSEARCH_PATH_CERTS="$work/config/certificates"
export OPENSEARCH_VARLOG="$work/logs"
mkdir -p "$SNAP/etc/ssl/certs/java" "$SNAP/usr/bin" \
    "$SNAP/usr/share/opensearch/shipped-plugins" "$SNAP/usr/share/opensearch/shipped-bin" \
    "$SNAP_DATA/usr/share/opensearch/plugins" "$SNAP_DATA/usr/share/opensearch/bin" \
    "$OPENSEARCH_PATH_CERTS"
ln -s "$installed_snap/usr/bin/setpriv" "$SNAP/usr/bin/setpriv"
printf '%s\n' '-XX:HeapDumpPath=operator-selected' > "$OPENSEARCH_PATH_CONF/jvm.options"
chmod 770 "$work" "$OPENSEARCH_PATH_CONF"
chmod 770 "$SNAP_DATA/usr/share/opensearch/bin"
chmod 660 "$OPENSEARCH_PATH_CONF/jvm.options"
chown snap_daemon:root "$work" "$OPENSEARCH_PATH_CONF" \
    "$OPENSEARCH_PATH_CONF/jvm.options" "$SNAP_DATA/usr/share/opensearch/bin"

# Native keytool creates small real stores; no certificate handling is mocked.
for certificate in old new custom; do
    openssl req -x509 -newkey rsa:2048 -nodes -days 2 -subj "/CN=$certificate" \
        -keyout "$certificate.key" -out "$certificate.pem" > /dev/null 2>&1
done
import_certificate() {
    "$keytool" -importcert -noprompt -storepass changeit -keystore "$1" \
        -alias "$2" -file "$3" > /dev/null 2>&1
}
for alias in debian:removed debian:replaced debian:deleted; do
    import_certificate "$work/old.p12" "$alias" old.pem
done
for alias in debian:added debian:replaced debian:deleted; do
    import_certificate "$work/new.p12" "$alias" new.pem
done
store="$OPENSEARCH_PATH_CERTS/cacerts.p12"
cp "$work/old.p12" "$store"
cp "$work/new.p12" "$SNAP/etc/ssl/certs/java/cacerts"
import_certificate "$store" 'my custom CA, with spaces' custom.pem
import_certificate "$store" custom-deleted custom.pem
for alias in custom-deleted debian:deleted debian:replaced; do
    "$keytool" -delete -storepass changeit -keystore "$store" -alias "$alias"
done
import_certificate "$store" debian:replaced custom.pem
# Even an accidentally imported private key under a bundled alias must be replaced.
"$keytool" -delete -storepass changeit -keystore "$store" -alias debian:replaced
for alias in debian:replaced custom-key; do
    "$keytool" -genkeypair -alias "$alias" -dname 'CN=custom-key' -keyalg RSA \
        -keystore "$store" -storepass changeit -keypass changeit > /dev/null 2>&1
done
chmod 660 "$store"
chown snap_daemon:root "$store"

has_alias() {
    "$keytool" -list -storepass changeit -keystore "$store" -alias "$1" > /dev/null 2>&1
}
expect_certificate() {
    "$keytool" -exportcert -storepass changeit -keystore "$store" -alias "$1" \
        -file actual.der > /dev/null 2>&1
    openssl x509 -in "$2" -outform DER -out expected.der
    cmp actual.der expected.der
}

# Refresh follows the package, overriding manual edits only in its reserved namespace.
bash "$standard/snap/hooks/post-refresh" > hook.log 2>&1 || { cat hook.log; exit 1; }
if has_alias debian:removed; then
    echo 'FAIL: refresh retains a CA removed from the bundled truststore' >&2
    exit 1
fi
expect_certificate debian:added new.pem
expect_certificate debian:replaced new.pem
expect_certificate debian:deleted new.pem
expect_certificate 'my custom CA, with spaces' custom.pem
"$keytool" -certreq -alias custom-key -storepass changeit -keystore "$store" -file custom.csr
! has_alias custom-deleted
test "$(stat -c '%a %U:%G' "$store")" = '660 snap_daemon:root'
echo 'PASS: refresh updates bundled CAs and preserves custom additions and deletions'

# A same-bundle refresh must also undo a manual deletion of a bundled entry.
"$keytool" -delete -storepass changeit -keystore "$store" -alias debian:deleted
bash "$standard/snap/hooks/post-refresh" > hook.log 2>&1 || { cat hook.log; exit 1; }
expect_certificate debian:deleted new.pem
! has_alias custom-deleted
echo 'PASS: same-bundle refresh restores bundled entries without restoring custom deletions'

# Startup after revert selects the previous bundle, retaining the same custom entries.
refresh="$standard/scripts/helpers/refresh-trust-store.sh"
cp "$work/old.p12" "$SNAP/etc/ssl/certs/java/cacerts"
bash "$refresh"
expect_certificate debian:removed old.pem
expect_certificate debian:replaced old.pem
expect_certificate debian:deleted old.pem
! has_alias debian:added
expect_certificate 'my custom CA, with spaces' custom.pem
! has_alias custom-deleted
sha256sum "$store" > unchanged.sha256
bash "$refresh"
sha256sum -c unchanged.sha256
echo 'PASS: revert follows its bundle; ordinary unchanged startup does not rewrite the store'

# Invalid input must leave the working store and the last successful bundle hash intact.
sha256sum "$store" "$OPENSEARCH_PATH_CERTS/cacerts-bundle.sha256" > failure.sha256
printf 'invalid keystore\n' > "$SNAP/etc/ssl/certs/java/cacerts"
if bash "$refresh" > failure.log 2>&1; then
    echo 'FAIL: corrupt bundle was accepted' >&2
    exit 1
fi
sha256sum -c failure.sha256
echo 'PASS: a corrupt bundle leaves the live truststore unchanged'

# Interrupt after publishing B but before recording success, then roll back to A.
# The old success record must not make startup skip recovery of A's bundled CAs.
cp "$work/new.p12" "$SNAP/etc/ssl/certs/java/cacerts"
mkdir "$work/bin"
export TRUSTSTORE_REAL_MV
TRUSTSTORE_REAL_MV=$(command -v mv)
cat > "$work/bin/mv" <<'EOF'
#!/usr/bin/env bash
"$TRUSTSTORE_REAL_MV" "$@" || exit
if [ "${*: -1}" = "$OPENSEARCH_PATH_CERTS/cacerts.p12" ]; then
    kill -TERM "$PPID"
    exit 143
fi
EOF
chmod +x "$work/bin/mv"
if PATH="$work/bin:$PATH" bash "$refresh" refresh > interrupted.log 2>&1; then
    echo 'FAIL: interrupted update reported success' >&2
    exit 1
fi
cp "$work/old.p12" "$SNAP/etc/ssl/certs/java/cacerts"
bash "$refresh"
if ! expect_certificate debian:removed old.pem; then
    echo 'FAIL: rollback skipped recovery after an interrupted truststore publication' >&2
    exit 1
fi
! has_alias debian:added
expect_certificate 'my custom CA, with spaces' custom.pem
echo 'PASS: rollback recovers the right bundle after interrupted publication'

# Installation creates the writable store directly from the active bundle.
cp "$work/new.p12" "$SNAP/etc/ssl/certs/java/cacerts"
mkdir "$work/fresh"
OPENSEARCH_PATH_CERTS="$work/fresh" bash "$refresh"
store="$work/fresh/cacerts.p12"
expect_certificate debian:added new.pem
! has_alias 'my custom CA, with spaces'
test "$(stat -c '%a' "$store")" = 660
echo 'PASS: fresh installation imports the bundled CAs'

# An unexpected packaged namespace must never overwrite a separately named custom CA.
import_certificate "$SNAP/etc/ssl/certs/java/cacerts" company-root custom.pem
sha256sum "$store" > namespace.sha256
if OPENSEARCH_PATH_CERTS="$work/fresh" bash "$refresh" refresh > namespace.log 2>&1; then
    echo 'FAIL: an unexpected packaged alias was accepted' >&2
    exit 1
fi
sha256sum -c namespace.sha256
echo 'PASS: unexpected bundled aliases leave custom entries and the live store untouched'
