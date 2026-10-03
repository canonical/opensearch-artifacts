#!/usr/bin/env bash
# Run under snap run --shell opensearch.opensearch-bin, passing a copy of the
# standard snap source directory. The real hooks only see disposable test data.
# shellcheck disable=SC1090,SC1091
set -euo pipefail
umask 0007

source_directory="$1"
test_directory=$(mktemp -d "${SNAP_COMMON}/heap-path-test.XXXXXX")
trap 'rm -rf -- "${test_directory}"' EXIT
export OPENSEARCH_PATH_CONF="${test_directory}/config"
export OPENSEARCH_VARLOG="${test_directory}/logs"
export OPENSEARCH_VARLIB="${test_directory}/data"
export SNAP_DATA="${test_directory}/revision"
export SNAP_LOG_DIR="${test_directory}/hook-logs"
mkdir -p "${OPENSEARCH_PATH_CONF}" "${OPENSEARCH_VARLOG}" \
    "${SNAP_DATA}/usr/share/opensearch/plugins" "${SNAP_DATA}/usr/share/opensearch/bin"
chmod 770 "${test_directory}" "${OPENSEARCH_PATH_CONF}" "${OPENSEARCH_VARLOG}"
chown -R snap_daemon:root "${test_directory}"
source "${OPS_ROOT}/helpers/set-conf.sh"

# Load only the real install configuration function, without bootstrapping a node.
source <(sed -n '/^function set_base_config_props () {/,/^}/p' "${source_directory}/snap/hooks/install")
expected_option="-XX:HeapDumpPath=${OPENSEARCH_VARLOG}/java_heapdump.hprof"

# Both fresh installation and refresh must migrate the old relative default.
for lifecycle in install refresh; do
    printf '%s\n' '---' > "${OPENSEARCH_PATH_CONF}/opensearch.yml"
    printf '%s\n' '# -XX:HeapDumpPath=data' '-XX:HeapDumpPath=data' '-Xmx32m' > "${OPENSEARCH_PATH_CONF}/jvm.options"
    chmod 660 "${OPENSEARCH_PATH_CONF}/jvm.options"
    chown snap_daemon:root "${OPENSEARCH_PATH_CONF}/jvm.options"
    if [ "${lifecycle}" = install ]; then
        set_base_config_props
    else
        bash "${source_directory}/snap/hooks/post-refresh"
    fi
    grep -Fx -- "${expected_option}" "${OPENSEARCH_PATH_CONF}/jvm.options"
    grep -Fx -- '# -XX:HeapDumpPath=data' "${OPENSEARCH_PATH_CONF}/jvm.options"
    test "$(stat -c '%a %U:%G' "${OPENSEARCH_PATH_CONF}/jvm.options")" = '660 snap_daemon:root'
    echo "PASS: ${lifecycle} selects a writable dump path and preserves permissions."
done

# Refresh must be repeatable and leave an operator's selected path untouched.
for dump_option in "${expected_option}" '-XX:HeapDumpPath=/custom/dumps' '-XX:HeapDumpPath=custom-relative-path'; do
    printf '%s\n' "${dump_option}" '-Xmx32m' > "${OPENSEARCH_PATH_CONF}/jvm.options"
    before=$(sha256sum "${OPENSEARCH_PATH_CONF}/jvm.options")
    bash "${source_directory}/snap/hooks/post-refresh"
    test "$(sha256sum "${OPENSEARCH_PATH_CONF}/jvm.options")" = "${before}"
done

# Exercise the resulting JVM option with a tiny independent heap, not the server.
printf '%s\n' "${expected_option}" > "${OPENSEARCH_PATH_CONF}/jvm.options"
cp "${source_directory}/tests/HeapDumpProbe.java" "${test_directory}/HeapDumpProbe.java"
chmod 644 "${test_directory}/HeapDumpProbe.java"
cd "${OPENSEARCH_HOME}"
"${SNAP}/usr/bin/setpriv" --clear-groups --reuid snap_daemon --regid snap_daemon -- \
    "${JAVA_HOME}/bin/java" -Xmx32m -XX:+HeapDumpOnOutOfMemoryError \
    "$(cat "${OPENSEARCH_PATH_CONF}/jvm.options")" "${test_directory}/HeapDumpProbe.java" > "${test_directory}/first.log" 2>&1 && exit 1
cat "${test_directory}/first.log"
grep -q 'Heap dump file created' "${test_directory}/first.log"
test -s "${OPENSEARCH_VARLOG}/java_heapdump.hprof"
before=$(sha256sum "${OPENSEARCH_VARLOG}/java_heapdump.hprof")

# A fixed filename retains the first dump instead of accumulating one per crash.
"${SNAP}/usr/bin/setpriv" --clear-groups --reuid snap_daemon --regid snap_daemon -- \
    "${JAVA_HOME}/bin/java" -Xmx32m -XX:+HeapDumpOnOutOfMemoryError \
    "${expected_option}" "${test_directory}/HeapDumpProbe.java" > "${test_directory}/second.log" 2>&1 && exit 1
cat "${test_directory}/second.log"
grep -qi 'File exists' "${test_directory}/second.log"
test "$(sha256sum "${OPENSEARCH_VARLOG}/java_heapdump.hprof")" = "${before}"
echo 'PASS: actual dump created; a repeated OOM preserves the first dump.'
