#!/usr/bin/env bash

set -eu


exec "${SNAP}"/usr/bin/setpriv \
    --clear-groups \
    --reuid snap_daemon \
    --regid snap_daemon -- \
    "${OPENSEARCH_DASHBOARDS_BIN}"/opensearch-dashboards-keystore "$@"
