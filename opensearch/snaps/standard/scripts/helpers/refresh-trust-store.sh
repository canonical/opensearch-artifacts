#!/usr/bin/env bash
set -euo pipefail
umask 007

certificates=${OPENSEARCH_PATH_CERTS}
store="$certificates/cacerts.p12"
bundle="$SNAP/etc/ssl/certs/java/cacerts"
keytool=("$JAVA_HOME/bin/keytool" -J-Duser.language=en -J-Duser.country=US)

# Restarts need no work if the revision and bundle are unchanged. Refresh restores its CAs,
# including bundled entries someone may have edited or deleted by hand.
bundle_checksum=$(sha256sum "$bundle")
if [ "${1:-}" != refresh ] && [ -f "$store" ] &&
    [ "$bundle_checksum" = "$(cat "$certificates/cacerts-bundle.sha256" 2>/dev/null || true)" ]; then
    exit 0
fi

# Work on a private copy so a failed keytool command cannot damage the live store.
temporary=$(mktemp -d "$certificates/.cacerts.XXXXXXXX")
trap 'rm -rf -- "$temporary"' EXIT
"${keytool[@]}" -list -rfc -storepass changeit -keystore "$bundle" > "$temporary/bundle.txt"
sed -n 's/^Alias name: //p' "$temporary/bundle.txt" | LC_ALL=C sort > "$temporary/bundle-aliases"

# Ubuntu reserves debian: aliases for its CA bundle; other aliases belong to users.
# Refuse an unexpected bundle before it can overwrite a user's separate entry.
if [ ! -s "$temporary/bundle-aliases" ] || grep -qv '^debian:' "$temporary/bundle-aliases"; then
    echo 'The bundled CA store must contain only debian: aliases.' >&2
    exit 1
fi

# Use the bundled JDK to import entries, retaining its diagnostic if an import fails.
import_keystore_entries() {
    "${keytool[@]}" -importkeystore -noprompt -srcstorepass changeit -deststorepass changeit \
        -destkeystore "$temporary/store.p12" -deststoretype PKCS12 "$@" \
        > "$temporary/import.log" 2>&1 || {
        cat "$temporary/import.log" >&2
        return 1
    }
}

# Start with the complete bundled store, then carry over only custom entries.
# This also discards any keys or certificates manually put under a bundled alias.
import_keystore_entries -srckeystore "$bundle" -srcstoretype JKS
touch "$temporary/custom-aliases"
if [ -f "$store" ]; then
    "${keytool[@]}" -list -rfc -storepass changeit -keystore "$store" > "$temporary/current.txt"
    sed -n '/^Alias name: debian:/d; s/^Alias name: //p' "$temporary/current.txt" > "$temporary/custom-aliases"
    while IFS= read -r alias; do
        import_keystore_entries -srckeystore "$store" -srcstoretype PKCS12 -srcalias "$alias"
    done < "$temporary/custom-aliases"
fi

# Keytool can skip individual failed imports, so require every expected alias.
"${keytool[@]}" -list -rfc -storepass changeit -keystore "$temporary/store.p12" > "$temporary/updated.txt"
sed -n 's/^Alias name: //p' "$temporary/updated.txt" | LC_ALL=C sort > "$temporary/updated-aliases"
cat "$temporary/bundle-aliases" "$temporary/custom-aliases" | LC_ALL=C sort > "$temporary/expected-aliases"
cmp "$temporary/expected-aliases" "$temporary/updated-aliases"

# Preserve access permissions and publish the complete store with one rename.
chmod 660 "$temporary/store.p12"
if [ -f "$store" ]; then
    chmod --reference="$store" "$temporary/store.p12"
    chown --reference="$store" "$temporary/store.p12"
fi
# Clear the old success record first so an interrupted update cannot fool rollback.
rm -f "$certificates/cacerts-bundle.sha256"
mv -f "$temporary/store.p12" "$store"

# Record success last. An interruption before this rename just repeats the update.
printf '%s\n' "$bundle_checksum" > "$temporary/bundle.sha256"
mv -f "$temporary/bundle.sha256" "$certificates/cacerts-bundle.sha256"
