#!/usr/bin/env bash

set -eu


if [ "$(id -u)" -ne 0 ]; then
    echo "error: must be run as root: sudo ${SNAP_INSTANCE_NAME}.keystore $*" >&2
    exit 1
fi

# The keystore is opensearch_dashboards.keystore in the configuration
# directory (OSD_PATH_CONF), which belongs to snap_daemon with the root group.
exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid root -- \
    "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards-keystore "$@"
