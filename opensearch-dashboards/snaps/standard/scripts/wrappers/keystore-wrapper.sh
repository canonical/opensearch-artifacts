#!/usr/bin/env bash

set -eu


# The keystore belongs to snap_daemon, which only root can switch to.
if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root: sudo opensearch-dashboards.keystore" >&2
    exit 1
fi

function as_snap_daemon () {
    "${SNAP}"/usr/bin/setpriv \
        --clear-groups \
        --reuid snap_daemon \
        --regid snap_daemon -- \
        "$@"
}

# The keystore is only obfuscated: only snap_daemon, which runs OpenSearch
# Dashboards, may read it. Upstream keeps the mode of an existing keystore, so
# one created readable by others is restricted first.
keystore="${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.keystore"
if [ -f "${keystore}" ]; then
    as_snap_daemon chmod 600 "${keystore}" \
        || echo "warning: could not restrict the permissions of ${keystore}" >&2
fi

umask 0077
exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid snap_daemon -- \
    "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards-keystore "$@"
