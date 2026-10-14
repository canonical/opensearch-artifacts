#!/usr/bin/env bash

set -eu

source "${OPS_ROOT}"/helpers/plugins.sh


function report_removed_plugins () {
    local line

    [ -s "${OSD_REMOVED_PLUGINS}" ] || return 0
    while read -r line; do
        echo "warning: ${line}" >&2
    done < "${OSD_REMOVED_PLUGINS}"
}


function start_opensearch_dashboards () {
    # The custom plugins are in the revision's data, linked from <home>/plugins:
    # resolve their modules (@osd/*, ../../src/...) from that link, as in the
    # upstream layout, instead of from their real path.
    export NODE_OPTIONS="--preserve-symlinks ${NODE_OPTIONS:-}"

    # start
    exec "${SNAP}"/usr/bin/setpriv \
        --clear-groups \
        --reuid snap_daemon \
        --regid snap_daemon -- \
        ${OPENSEARCH_DASHBOARDS_BIN}/opensearch-dashboards \
        -c ${OPENSEARCH_DASHBOARDS_PATH_CONF}/opensearch_dashboards.yml \
        -l ${OPENSEARCH_DASHBOARDS_VARLOG}/opensearch_dashboards.log

}

report_removed_plugins
start_opensearch_dashboards
