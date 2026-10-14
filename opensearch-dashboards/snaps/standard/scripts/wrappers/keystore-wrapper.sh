#!/usr/bin/env bash

set -eu


# The keystore belongs to snap_daemon, which only root can switch to.
if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root: sudo opensearch-dashboards.keystore" >&2
    exit 1
fi

exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid snap_daemon -- \
    "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards-keystore "$@"
