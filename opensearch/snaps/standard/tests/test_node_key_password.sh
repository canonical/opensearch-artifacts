#!/usr/bin/env bash
# Run inside `snap run --shell opensearch.setup` so the real TLS helpers and yq
# are available. All certificates and settings stay in a temporary directory.
# shellcheck disable=SC1091
set -euo pipefail

test_directory=$(mktemp -d "${SNAP_COMMON}/node-password-test.XXXXXX")
trap 'rm -rf -- "${test_directory}"' EXIT
export OPENSEARCH_PATH_CONF="${test_directory}/config"
export SNAP_LOG_DIR="${test_directory}/logs"
mkdir -p "${OPENSEARCH_PATH_CONF}"
configuration="${OPENSEARCH_PATH_CONF}/opensearch.yml"
certificates="${OPENSEARCH_PATH_CONF}/certificates"
printf 'cluster.name: password-regression\n' > "${configuration}"
bash "${OPS_ROOT}/helpers/create-certificate.sh" --type root --target-dir "${certificates}"

# Check the actual key as well as the settings OpenSearch will read on startup.
check_password() {
    local layer="$1" expected_password="$2" key_path
    # These variables belong to yq, not the shell.
    # shellcheck disable=SC2016
    "${SNAP}/usr/bin/yq" -e --arg layer "${layer}" --arg password "${expected_password}" '
        ("plugins.security.ssl." + $layer + ".pemkey_password") as $key |
        if $password == "" then has($key) | not else .[$key] == $password end
    ' "${configuration}" > /dev/null || {
        echo "FAIL: ${layer} password setting does not match the new key's encryption." >&2
        return 1
    }
    key_path=$("${SNAP}/usr/bin/yq" -r ".\"plugins.security.ssl.${layer}.pemkey_filepath\"" "${configuration}")
    # OpenSearch resolves relative certificate paths from its configuration directory.
    if [[ "${key_path}" != /* ]]; then
        key_path="${OPENSEARCH_PATH_CONF}/${key_path}"
    fi
    openssl pkey -in "${key_path}" -passin "pass:${expected_password}" -noout
}

# Use a fixed subject and SAN to keep these checks independent of VM networking.
rotate_node() {
    bash "${OPS_ROOT}/security/tls/self-managed-node.sh" \
        --name regression --target-dir "${certificates}" \
        --node-subject /CN=password-regression --sans DNS:localhost "$@"
}

# Transport-only setup must also work when HTTP has no key configured yet.
rotate_node --rest-with-tls no
check_password transport ""
"${SNAP}/usr/bin/yq" -e 'has("plugins.security.ssl.http.pemkey_filepath") | not' "${configuration}" > /dev/null

# Fresh unencrypted setup must work without either password setting.
rotate_node --rest-with-tls yes
check_password transport ""
check_password http ""

# Adding encryption and changing its password must update both layers.
for password in test-first-password test-second-password; do
    rotate_node --rest-with-tls yes --node-password "${password}"
    check_password transport "${password}"
    check_password http "${password}"
done

# Omitting the password must remove the previous encrypted key's settings.
rotate_node --rest-with-tls yes
check_password transport ""
check_password http ""

# An explicitly empty password must have the same effect, including on repeat.
rotate_node --rest-with-tls yes --node-password test-third-password
for attempt in 1 2; do
    rotate_node --rest-with-tls yes --node-password ""
    check_password transport ""
    check_password http ""
    echo "PASS: explicitly empty password, attempt ${attempt}."
done

# Preserve a separate encrypted HTTP key when rotating only the transport key.
rotate_node --rest-with-tls yes --node-password test-http-password
http_key="${certificates}/separate-http-key.pem"
cp "${certificates}/node-regression-key.pem" "${http_key}"
source "${OPS_ROOT}/helpers/set-conf.sh"
set_yaml_prop "${configuration}" plugins.security.ssl.http.pemkey_filepath "${http_key}"
http_settings_before=$("${SNAP}/usr/bin/yq" -c 'with_entries(select(.key | startswith("plugins.security.ssl.http.")))' "${configuration}")
rotate_node --rest-with-tls no
check_password transport ""
check_password http test-http-password
http_settings_after=$("${SNAP}/usr/bin/yq" -c 'with_entries(select(.key | startswith("plugins.security.ssl.http.")))' "${configuration}")
test "${http_settings_before}" = "${http_settings_after}"

# A transport-only rotation still changes HTTP's key if both refer to the same file.
rotate_node --rest-with-tls yes --node-password test-shared-password
rotate_node --rest-with-tls no
check_password transport ""
check_password http ""
rotate_node --rest-with-tls no --node-password test-shared-new-password
check_password transport test-shared-new-password
check_password http test-shared-new-password

# Relative HTTP paths must identify the same shared key, even with the flag omitted.
set_yaml_prop "${configuration}" plugins.security.ssl.http.pemkey_filepath certificates/node-regression-key.pem
rotate_node
check_password transport ""
check_password http ""

# A symlink to the shared key must get the same password update.
ln -s node-regression-key.pem "${certificates}/http-key-link.pem"
set_yaml_prop "${configuration}" plugins.security.ssl.http.pemkey_filepath certificates/http-key-link.pem
rotate_node --rest-with-tls no --node-password test-symlink-password
check_password transport test-symlink-password
check_password http test-symlink-password
"${SNAP}/usr/bin/yq" -e '."cluster.name" == "password-regression"' "${configuration}" > /dev/null
echo 'PASS: node key passwords follow encryption; separate HTTP settings are preserved.'

# A nested HTTP setting still refers to the shared key during transport-only rotation.
rotate_node --rest-with-tls yes --node-password test-nested-password
"${SNAP}/usr/bin/yq" -y -i '
    .plugins.security.ssl.http = {
        pemkey_filepath: ."plugins.security.ssl.http.pemkey_filepath",
        pemkey_password: ."plugins.security.ssl.http.pemkey_password"
    } | del(."plugins.security.ssl.http.pemkey_filepath", ."plugins.security.ssl.http.pemkey_password")
' "${configuration}"
rotate_node --rest-with-tls no
"${SNAP}/usr/bin/yq" -e '
    (.plugins.security.ssl.http | has("pemkey_password") | not)
    and (has("plugins.security.ssl.http.pemkey_password") | not)
' "${configuration}" > /dev/null
openssl pkey -in "${certificates}/node-regression-key.pem" -passin pass: -noout

# Encrypting the same key must also update HTTP when its path remains nested.
rotate_node --rest-with-tls no --node-password test-nested-new-password
"${SNAP}/usr/bin/yq" -e '."plugins.security.ssl.http.pemkey_password" == "test-nested-new-password"' "${configuration}" > /dev/null
openssl pkey -in "${certificates}/node-regression-key.pem" -passin pass:test-nested-new-password -noout
echo 'PASS: nested HTTP paths follow shared-key encryption changes.'
